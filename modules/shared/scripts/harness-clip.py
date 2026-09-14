#!/usr/bin/env python3
"""Harness-agnostic EPR/obs-pack clipper for Cursor Agent CLI and Muse Code.

Reads one JSON object from stdin (hook payload). If the body looks like a
diagnostic cargo/test log ≥4 KiB, archives it under ~/.pi/agent/epr/ and
prints a short receipt JSON. Fail-open. Local only — no cloud reducer.

Keep DIAGNOSTIC_COMMAND in sync with pi-extensions/epr.ts.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

MIN_BYTES = 4096
PREVIEW_HEAD = 2048
PREVIEW_TAIL = 1536
MAX_SCOUT = 12
MAX_QUOTE = 600

DIAGNOSTIC_COMMAND = re.compile(
    r"(?:^|[;&|()\s])(?:cargo(?:\s+(?:build|test|check|nextest))?|"
    r"cmake\s+--build|ctest|ninja|make|pytest|"
    r"python(?:3)?\s+-m\s+(?:pytest|unittest|py_compile)|"
    r"npm\s+test|pnpm\s+test|yarn\s+test|go\s+test|bazel\s+test)(?:\s|$)",
    re.I,
)
FAILURE_SIGNAL = re.compile(
    r"error|failed|failure|fatal|exception|panic|timeout|unsolved|"
    r"type mismatch|assert",
    re.I,
)
LIKELY_SECRET = re.compile(
    r"(?:api[_-]?key|authorization|bearer|access[_-]?token|secret)"
    r"[^\n]{0,32}[=:][^\n]+",
    re.I,
)


def dump_dir() -> Path:
    return Path.home() / ".pi" / "agent" / "epr"


def as_record(value: object) -> dict:
    return value if isinstance(value, dict) else {}


def first_str(*values: object) -> str:
    for value in values:
        if isinstance(value, str) and value.strip():
            return value
        if isinstance(value, list):
            parts = []
            for item in value:
                if isinstance(item, str):
                    parts.append(item)
                elif isinstance(item, dict) and isinstance(item.get("text"), str):
                    parts.append(item["text"])
            joined = "\n".join(parts).strip()
            if joined:
                return joined
    return ""


def detect_harness(payload: dict) -> str:
    explicit = os.environ.get("ADVAIT_HARNESS", "").strip().lower()
    if explicit in {"cursor", "muse", "pi"}:
        return explicit
    if "exitCode" in payload or "command" in payload:
        return "cursor"
    if "event" in payload or "tool_name" in payload or "toolName" in payload:
        return "muse"
    return "unknown"


def command_of(payload: dict) -> str:
    rec = payload
    input_rec = as_record(rec.get("input") or rec.get("arguments") or rec.get("stdin"))
    return first_str(
        rec.get("command"),
        rec.get("cmd"),
        input_rec.get("command"),
        rec.get("tool_input") if isinstance(rec.get("tool_input"), str) else None,
        as_record(rec.get("tool_input")).get("command"),
    )


def body_of(payload: dict) -> str:
    rec = payload
    result = as_record(rec.get("result") or rec.get("tool_result") or rec.get("output"))
    return first_str(
        rec.get("output"),
        rec.get("stdout"),
        rec.get("text"),
        rec.get("content"),
        result.get("output"),
        result.get("stdout"),
        result.get("text"),
        result.get("content"),
        rec.get("tool_output"),
    )


def scout(body: str) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for raw in body.splitlines():
        line = raw.rstrip()
        if len(line) < 8 or len(line) > MAX_QUOTE:
            continue
        if not FAILURE_SIGNAL.search(line):
            continue
        if line in seen:
            continue
        seen.add(line)
        out.append(line)
        if len(out) >= MAX_SCOUT:
            break
    return out


def redact(body: str) -> str:
    return LIKELY_SECRET.sub("[redacted-secret]", body)


def is_pre_tool(payload: dict) -> bool:
    event = first_str(
        payload.get("hook_event_name"),
        payload.get("event"),
        payload.get("hookEventName"),
    ).lower()
    return event in {"pretooluse", "pre_tool_use"} and not body_of(payload)


def wrap_diagnostic(command: str) -> str | None:
    if not command or "ADVAIT_EPR_LOG=" in command:
        return None
    if not DIAGNOSTIC_COMMAND.search(command):
        return None
    dump_dir().mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    log = dump_dir() / f"cli-tee-{stamp}.log"
    # Tee so the model still sees the log; archive path is deterministic.
    return (
        f"{{ {command} ; }} > >(tee {log!s}) 2>&1; "
        f"ec=$?; echo ADVAIT_EPR_LOG={log} >&2; exit $ec"
    )


def should_clip(command: str, body: str) -> bool:
    if len(body.encode("utf-8")) < MIN_BYTES:
        return False
    blob = f"{command}\n{body}"
    return bool(DIAGNOSTIC_COMMAND.search(command) or DIAGNOSTIC_COMMAND.search(blob[:2000]))


def archive(harness: str, command: str, body: str) -> Path:
    dump_dir().mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256(body.encode("utf-8")).hexdigest()[:16]
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = dump_dir() / f"cli-{harness}-{stamp}-{digest}.log"
    header = f"# command: {command}\n# harness: {harness}\n# bytes: {len(body.encode('utf-8'))}\n\n"
    path.write_text(header + redact(body), encoding="utf-8")
    return path


def receipt(path: Path, command: str, body: str, quotes: list[str]) -> str:
    status = "failure" if FAILURE_SIGNAL.search(body.lower()) else "success"
    if re.search(r"test result:\s*ok", body, re.I) or re.search(
        r"\d+ passed;\s*0 failed", body, re.I
    ):
        status = "success"
    lines = [
        "advait_epr_v1",
        f"status={status}",
        f"command_sha256={hashlib.sha256(command.encode()).hexdigest()}",
        f"source_bytes={len(body.encode('utf-8'))}",
        f"source_artifact={path}",
        "reducer=harness-clip",
        "verified_evidence:",
    ]
    for quote in quotes[:MAX_SCOUT]:
        lines.append(f"- quote={json.dumps(quote)}")
    lines.append("readback=read the source_artifact for exact context")
    return "\n".join(lines)


def cursor_out(text: str) -> dict:
    return {"permission": "allow", "additional_context": text, "agent_message": text}


def muse_out(text: str) -> dict:
    # Fail-open allow; attach receipt if the CLI honors additionalContext.
    return {"permission": "allow", "additionalContext": text, "systemMessage": text}


def pass_through(harness: str) -> dict:
    if harness == "muse":
        return {"permission": "allow"}
    return {"permission": "allow"}


def main() -> int:
    raw = sys.stdin.read()
    if not raw.strip():
        json.dump({"permission": "allow"}, sys.stdout)
        return 0
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        json.dump({"permission": "allow"}, sys.stdout)
        return 0
    if not isinstance(payload, dict):
        json.dump({"permission": "allow"}, sys.stdout)
        return 0
    harness = detect_harness(payload)
    command = command_of(payload)
    body = body_of(payload)
    if is_pre_tool(payload):
        wrapped = wrap_diagnostic(command)
        if wrapped:
            json.dump(
                {
                    "permission": "allow",
                    "updated_input": {"command": wrapped},
                },
                sys.stdout,
            )
            return 0
        json.dump(pass_through(harness), sys.stdout)
        return 0
    if not should_clip(command, body):
        json.dump(pass_through(harness), sys.stdout)
        return 0
    path = archive(harness, command or "(unknown)", body)
    quotes = scout(body)
    text = receipt(path, command or "(unknown)", body, quotes)
    preview = (
        body[:PREVIEW_HEAD]
        + ("\n…\n" if len(body) > PREVIEW_HEAD + PREVIEW_TAIL else "")
        + (body[-PREVIEW_TAIL:] if len(body) > PREVIEW_HEAD + PREVIEW_TAIL else "")
    )
    note = f"{text}\n\npreview:\n{preview[:1200]}"
    out = muse_out(note) if harness == "muse" else cursor_out(note)
    json.dump(out, sys.stdout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
