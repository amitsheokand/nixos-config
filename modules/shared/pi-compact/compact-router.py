#!/usr/bin/env python3
"""OpenAI-compat compact router: Mac Compactor first, local tiny fallback.

Never forwards to hipfire (:11435) or the desktop catalog proxy (:8080).
Injects focus.md and forces thinking off so a tiny fallback stays on-task.
"""
from __future__ import annotations

import json
import os
import sys
from http.client import HTTPConnection, HTTPSConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

FOCUS_PATH = Path(__file__).with_name("focus.md")
BLOCKED = {
    ("127.0.0.1", 11435),
    ("localhost", 11435),
    ("127.0.0.1", 8080),
    ("localhost", 8080),
    ("nixos.local", 11435),
    # Gemma coder lane on the Mac — compact belongs on :8081.
    ("ai-mac.local", 8080),
    ("ai-mac", 8080),
}


def load_focus() -> str:
    path = os.environ.get("COMPACT_FOCUS_FILE", str(FOCUS_PATH))
    try:
        return Path(path).read_text(encoding="utf-8").strip()
    except OSError:
        return (
            "You are a continuation-summary model. Preserve Task, facts, and "
            "the next step. Never invent a new project. Thinking off. No tools."
        )


def parse_base(url: str) -> tuple[str, str, int, str]:
    parsed = urlparse(url if "://" in url else f"http://{url}")
    host = parsed.hostname or "127.0.0.1"
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    prefix = parsed.path.rstrip("/") or ""
    return parsed.scheme or "http", host, port, prefix


def is_blocked(url: str) -> bool:
    _, host, port, _ = parse_base(url)
    return (host, port) in BLOCKED


def message_text(content: Any) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts: list[str] = []
        for part in content:
            if isinstance(part, str):
                parts.append(part)
            elif isinstance(part, dict) and part.get("type") == "text":
                parts.append(str(part.get("text") or ""))
        return "\n".join(parts)
    return str(content or "")


def prepare_body(raw: dict[str, Any], focus: str) -> dict[str, Any]:
    body = dict(raw)
    incoming = list(body.get("messages") or [])
    systems: list[str] = []
    rest: list[dict[str, Any]] = []
    for msg in incoming:
        if not isinstance(msg, dict):
            continue
        role = msg.get("role")
        if role in {"system", "developer"}:
            systems.append(message_text(msg.get("content")))
        else:
            rest.append(msg)
    if focus.strip() and not any("continuation-summary" in s for s in systems):
        systems.insert(0, focus)
    messages: list[dict[str, Any]] = []
    joined = "\n\n".join(s.strip() for s in systems if s and s.strip())
    if joined:
        messages.append({"role": "system", "content": joined})
    messages.extend(rest)
    body["messages"] = messages
    kwargs = dict(body.get("chat_template_kwargs") or {})
    kwargs["enable_thinking"] = False
    body["chat_template_kwargs"] = kwargs
    body["temperature"] = 0
    body.pop("reasoning_effort", None)
    body.pop("max_think_tokens", None)
    return body


def post_chat(base: str, body: dict[str, Any], timeout: float) -> tuple[int, dict[str, str], bytes]:
    if is_blocked(base):
        raise RuntimeError(f"refusing hipfire/catalog URL {base}")
    scheme, host, port, prefix = parse_base(base)
    path = f"{prefix}/chat/completions"
    payload = json.dumps(body).encode("utf-8")
    conn_cls = HTTPSConnection if scheme == "https" else HTTPConnection
    conn = conn_cls(host, port, timeout=timeout)
    try:
        conn.request(
            "POST",
            path,
            body=payload,
            headers={"Content-Type": "application/json", "Content-Length": str(len(payload))},
        )
        resp = conn.getresponse()
        data = resp.read()
        headers = {k: v for k, v in resp.getheaders()}
        return resp.status, headers, data
    finally:
        conn.close()


def rewrite_model(body: dict[str, Any], override: str | None) -> dict[str, Any]:
    out = dict(body)
    if override:
        out["model"] = override
    return out


def backends() -> list[tuple[str, str, str | None, float]]:
    """(name, base, model_override, timeout_s)."""
    primary = os.environ.get("COMPACT_PRIMARY_BASE", "http://ai-mac.local:8081/v1")
    fallback = os.environ.get("COMPACT_FALLBACK_BASE", "http://127.0.0.1:8092/v1")
    primary_model = os.environ.get("COMPACT_PRIMARY_MODEL") or None
    fallback_model = os.environ.get("COMPACT_FALLBACK_MODEL") or None
    primary_t = float(os.environ.get("COMPACT_PRIMARY_TIMEOUT_S", "60"))
    fallback_t = float(os.environ.get("COMPACT_FALLBACK_TIMEOUT_S", "120"))
    out = [("primary", primary, primary_model, primary_t)]
    if fallback and fallback != primary:
        out.append(("fallback", fallback, fallback_model, fallback_t))
    return out


class Handler(BaseHTTPRequestHandler):
    focus = load_focus()

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("pi-compact-router: " + (fmt % args) + "\n")

    def _send(self, status: int, payload: dict[str, Any], extra: dict[str, str] | None = None) -> None:
        raw = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self) -> None:  # noqa: N802
        if self.path.rstrip("/") in {"/v1/models", "/models"}:
            self._send(
                200,
                {
                    "object": "list",
                    "data": [
                        {
                            "id": "compactor",
                            "object": "model",
                            "owned_by": "pi-compact",
                            "context_window": 16384,
                        }
                    ],
                },
            )
            return
        self._send(404, {"error": {"message": "not found", "type": "invalid_request_error"}})

    def do_POST(self) -> None:  # noqa: N802
        if self.path.rstrip("/") not in {"/v1/chat/completions", "/chat/completions"}:
            self._send(404, {"error": {"message": "not found", "type": "invalid_request_error"}})
            return
        length = int(self.headers.get("Content-Length", "0") or "0")
        try:
            raw = json.loads(self.rfile.read(length) if length else b"{}")
        except json.JSONDecodeError:
            self._send(400, {"error": {"message": "invalid json", "type": "invalid_request_error"}})
            return
        if not isinstance(raw, dict):
            self._send(400, {"error": {"message": "body must be object", "type": "invalid_request_error"}})
            return
        prepared = prepare_body(raw, self.focus)
        errors: list[str] = []
        for name, base, model_override, timeout in backends():
            try:
                status, _headers, data = post_chat(
                    base, rewrite_model(prepared, model_override), timeout
                )
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{name} {base}: {exc}")
                continue
            if 200 <= status < 300:
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("X-Pi-Compact-Backend", name)
                self.end_headers()
                self.wfile.write(data)
                return
            errors.append(f"{name} {base}: HTTP {status} {data[:200]!r}")
        self._send(
            503,
            {
                "error": {
                    "message": "compact backends unavailable; not falling back to hipfire",
                    "type": "server_error",
                    "detail": errors,
                }
            },
            extra={"Retry-After": "5"},
        )


def main() -> None:
    host = os.environ.get("COMPACT_LISTEN_HOST", "127.0.0.1")
    port = int(os.environ.get("COMPACT_LISTEN_PORT", "8091"))
    Handler.focus = load_focus()
    httpd = ThreadingHTTPServer((host, port), Handler)
    print(f"pi-compact-router listening on {host}:{port}", file=sys.stderr)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
