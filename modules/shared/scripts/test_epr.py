#!/usr/bin/env python3
"""Unit tests for EPR scout/clip/verify. Keep regex in sync with epr.ts."""
from __future__ import annotations

import re
import unittest

DIAGNOSTIC_COMMAND = re.compile(
    r"(?:^|[;&|()\s])(?:cargo(?:\s+(?:build|test|check|nextest))?|cmake\s+--build|"
    r"ctest|ninja|make|pytest|python(?:3)?\s+-m\s+(?:pytest|unittest|py_compile)|"
    r"npm\s+test|pnpm\s+test|yarn\s+test|go\s+test|bazel\s+test)(?:\s|$)",
    re.I,
)
FAILURE_SIGNAL = re.compile(
    r"error|failed|failure|fatal|exception|panic|timeout|unsolved|type mismatch|assert",
    re.I,
)
LIKELY_SECRET = re.compile(
    r"(?:api[_-]?key|authorization|bearer|access[_-]?token|secret)[^\n]{0,32}[=:][^\n]+",
    re.I,
)
MAX_SCOUT_LINES = 12
MAX_QUOTE = 600
CLIP_HEAD = 20000
CLIP_TAIL = 12000


def scout_lines(body: str, max_n: int = MAX_SCOUT_LINES) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for raw in body.splitlines():
        line = raw.rstrip("\n")
        if len(line) < 8 or len(line) > MAX_QUOTE:
            continue
        if not FAILURE_SIGNAL.search(line):
            continue
        if line in seen:
            continue
        seen.add(line)
        out.append(line)
        if len(out) >= max_n:
            break
    return out


def clip_for_llm(body: str, scout: list[str]) -> str:
    if len(body) <= CLIP_HEAD + CLIP_TAIL:
        return body
    head = body[:CLIP_HEAD]
    tail = body[-CLIP_TAIL:]
    extra = [line for line in scout if line not in head and line not in tail]
    parts = [head]
    if extra:
        parts.append("\n".join(extra))
    if tail:
        parts.append(tail)
    return "\n…\n".join(parts)


def quotes_verified(quotes: list[str], body: str) -> bool:
    if not quotes or len(quotes) > MAX_SCOUT_LINES:
        return False
    return all(1 <= len(q) <= MAX_QUOTE and q in body for q in quotes)


class EprTests(unittest.TestCase):
    def test_diagnostic_cargo(self) -> None:
        self.assertTrue(DIAGNOSTIC_COMMAND.search("cargo test -p aikya-com"))
        self.assertTrue(DIAGNOSTIC_COMMAND.search("cargo build --workspace"))
        self.assertFalse(DIAGNOSTIC_COMMAND.search("ls crates"))
        self.assertFalse(DIAGNOSTIC_COMMAND.search("git status"))

    def test_skips_secrets(self) -> None:
        self.assertTrue(LIKELY_SECRET.search("authorization: Bearer sk-live-123"))
        self.assertFalse(LIKELY_SECRET.search("error: missing method release"))

    def test_scout_picks_failure_lines(self) -> None:
        log = (
            "   Compiling aikya-com v0.1.0\n"
            "error[E0599]: no method named `release` found for struct `Holder`\n"
            "   --> crates/aikya/nt/src/holder.rs:88:12\n"
            "error: could not compile `aikya-com` (lib test) due to 1 previous error\n"
            "test result: FAILED. 0 passed; 1 failed; 0 ignored\n"
        )
        scout = scout_lines(log)
        self.assertTrue(any("E0599" in line for line in scout))
        self.assertTrue(any("FAILED" in line for line in scout))
        self.assertTrue(quotes_verified(scout, log))

    def test_rejects_paraphrase(self) -> None:
        log = "error[E0599]: no method named `release` found\n"
        self.assertFalse(quotes_verified(["Holder is missing release()"], log))
        self.assertTrue(
            quotes_verified(
                ["error[E0599]: no method named `release` found"],
                log,
            )
        )

    def test_clip_passes_through_under_budget(self) -> None:
        body = "H" * 3000 + "\nerror: boom in the middle of the log\n" + "T" * 3000
        self.assertEqual(clip_for_llm(body, scout_lines(body, 40)), body)

    def test_clip_keeps_middle_scout(self) -> None:
        body = "H" * 25000 + "\nerror: boom in the middle of the log\n" + "T" * 25000
        scout = scout_lines(body, 40)
        clipped = clip_for_llm(body, scout)
        self.assertIn("error: boom in the middle of the log", clipped)
        self.assertLess(len(clipped), len(body))


def command_of(event: dict) -> str | None:
    """Keep in sync with epr.ts commandOf (Cursor Shell replay + then_run)."""
    details = event.get("details") if isinstance(event.get("details"), dict) else {}
    inp = event.get("input") if isinstance(event.get("input"), dict) else {}
    then = details.get("then_run")
    if isinstance(then, str) and then.strip():
        return then.strip()
    if isinstance(inp.get("then_run"), str) and inp["then_run"].strip():
        return inp["then_run"].strip()
    content = event.get("content") or []
    text = "".join(
        part.get("text", "") for part in content if isinstance(part, dict)
    )
    marker = re.search(r"\[then_run(?::(?:succeeded|failed))?]\s+([^\n]+)", text)
    if marker:
        return marker.group(1).strip()
    source = str(details.get("sourceToolName") or event.get("toolName") or "")
    shell = source.lower() in {"bash", "shell", "shelltool"}
    if not shell:
        return None
    if isinstance(inp.get("command"), str) and inp["command"].strip():
        return inp["command"].strip()
    if isinstance(details.get("command"), str) and details["command"].strip():
        return details["command"].strip()
    expanded = details.get("expandedText") if isinstance(details.get("expandedText"), str) else text
    dollar = re.search(r"^\s*\$\s+([^\n]+)", expanded, re.M)
    if dollar:
        return dollar.group(1).strip()
    return None


class EprCommandOfTests(unittest.TestCase):
    def test_native_bash_command(self) -> None:
        self.assertEqual(
            command_of({"toolName": "bash", "input": {"command": "cargo test -p aikya-com"}}),
            "cargo test -p aikya-com",
        )

    def test_cursor_shell_replay(self) -> None:
        event = {
            "toolName": "cursor",
            "details": {
                "sourceToolName": "bash",
                "expandedText": "$ cargo test -p aikya-com --lib\nerror: boom\n",
            },
            "content": [{"type": "text", "text": "$ cargo test -p aikya-com --lib\nerror: boom\n"}],
        }
        self.assertEqual(command_of(event), "cargo test -p aikya-com --lib")
        self.assertTrue(DIAGNOSTIC_COMMAND.search(command_of(event) or ""))

    def test_then_run_details(self) -> None:
        self.assertEqual(
            command_of(
                {
                    "toolName": "gate_edit",
                    "details": {"then_run": "cargo test -p aikya-com --lib"},
                }
            ),
            "cargo test -p aikya-com --lib",
        )

    def test_ignores_cursor_edit(self) -> None:
        self.assertIsNone(
            command_of(
                {
                    "toolName": "cursor",
                    "details": {"sourceToolName": "edit", "path": "src/lib.rs"},
                    "content": [{"type": "text", "text": "edit src/lib.rs\n@@ -1 +1 @@\n"}],
                }
            )
        )


if __name__ == "__main__":
    unittest.main()
