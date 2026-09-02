#!/usr/bin/env python3
"""Local Chat Completions proxy in front of https://api.meta.ai/v1.

Muse Spark reuses tool_call_id `call_0` every turn. Meta's Chat Completions
API requires those ids to be unique across the whole `messages` array, so a
second tool round from Zed / Pi / Hermes / Grok returns:

  Duplicate tool response for tool_call_id='call_0'

This proxy remaps assistant tool_calls and matching tool results to call_0,
call_1, … per request. OpenCode's Responses adapter talks to Meta directly
and does not need this.

Key: MODEL_API_KEY or META_API_KEY, from the environment or ~/.config/meta.env.
Never log the key.
"""
from __future__ import annotations

import http.client
import json
import os
import ssl
import sys
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

DEFAULT_BACKEND = "https://api.meta.ai"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8082
MODEL = "muse-spark-1.2"
HOP = {
    "connection",
    "keep-alive",
    "proxy-connection",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
    "host",
    "content-length",
}


def parse_meta_env_line(line: str) -> tuple[str, str] | None:
    """Parse one dotenv/zsh assignment. Accepts optional `export` and quotes."""
    stripped = line.strip()
    if stripped.startswith("\ufeff"):
        stripped = stripped.lstrip("\ufeff").strip()
    if not stripped or stripped.startswith("#") or "=" not in stripped:
        return None
    key, _, value = stripped.partition("=")
    key = key.strip()
    if key.startswith("export "):
        key = key[len("export ") :].strip()
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1]
    if not key or not value:
        return None
    return key, value


def load_meta_env() -> None:
    path = Path.home() / ".config" / "meta.env"
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        parsed = parse_meta_env_line(line)
        if parsed is None:
            continue
        key, value = parsed
        if not (os.environ.get(key) or "").strip():
            os.environ[key] = value


def api_key() -> str:
    return (
        os.environ.get("MODEL_API_KEY") or os.environ.get("META_API_KEY") or ""
    ).strip()


def uniquify_tool_call_ids(messages: list[Any]) -> list[Any]:
    """Give every tool_call a conversation-unique id, matching tool results."""
    n = 0
    pending: dict[str, deque[str]] = defaultdict(deque)
    out: list[Any] = []
    for message in messages:
        if not isinstance(message, dict):
            out.append(message)
            continue
        msg = dict(message)
        role = msg.get("role")
        if role == "assistant":
            tcs = msg.get("tool_calls")
            if isinstance(tcs, list) and tcs:
                pending = defaultdict(deque)
                new_tcs = []
                for tool_call in tcs:
                    if not isinstance(tool_call, dict):
                        new_tcs.append(tool_call)
                        continue
                    tool_call = dict(tool_call)
                    old = str(tool_call.get("id") or "call")
                    new = f"call_{n}"
                    n += 1
                    pending[old].append(new)
                    tool_call["id"] = new
                    new_tcs.append(tool_call)
                msg["tool_calls"] = new_tcs
        elif role == "tool":
            old = str(msg.get("tool_call_id") or "call")
            queue = pending.get(old)
            if queue:
                msg["tool_call_id"] = queue.popleft()
            else:
                msg["tool_call_id"] = f"call_{n}"
                n += 1
        out.append(msg)
    return out


def apply_chat_request(body: dict[str, Any]) -> dict[str, Any]:
    out = dict(body)
    messages = out.get("messages")
    if isinstance(messages, list):
        out["messages"] = uniquify_tool_call_ids(messages)
    return out


def is_completion_path(path: str) -> bool:
    clean = path.split("?", 1)[0].rstrip("/")
    return clean.endswith("/chat/completions") or clean.endswith("/completions")


def models_payload() -> bytes:
    return json.dumps(
        {
            "object": "list",
            "data": [
                {
                    "id": MODEL,
                    "object": "model",
                    "owned_by": "meta",
                }
            ],
        }
    ).encode()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    backend = DEFAULT_BACKEND
    backend_host = "api.meta.ai"
    backend_port = 443
    backend_scheme = "https"

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _send_bytes(self, status: int, payload: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(payload)

    def _connect(self) -> http.client.HTTPConnection:
        if self.backend_scheme == "https":
            return http.client.HTTPSConnection(
                self.backend_host,
                self.backend_port,
                timeout=3600,
                context=ssl.create_default_context(),
            )
        return http.client.HTTPConnection(
            self.backend_host, self.backend_port, timeout=3600
        )

    def _proxy(self) -> None:
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(length) if length else b""
        data = raw
        if self.command == "POST" and raw and is_completion_path(self.path):
            try:
                body = json.loads(raw.decode())
            except json.JSONDecodeError:
                self._send_bytes(
                    400,
                    b'{"error":{"message":"invalid json"}}',
                    "application/json",
                )
                return
            if isinstance(body, dict):
                data = json.dumps(apply_chat_request(body)).encode()

        key = api_key()
        if not key:
            self._send_bytes(
                401,
                json.dumps(
                    {
                        "error": {
                            "message": (
                                "muse-spark-proxy: missing MODEL_API_KEY "
                                "(put it in ~/.config/meta.env)"
                            )
                        }
                    }
                ).encode(),
                "application/json",
            )
            return

        headers = {
            key_name: value
            for key_name, value in self.headers.items()
            if key_name.lower() not in HOP
        }
        headers["Host"] = self.backend_host
        headers["Authorization"] = "Bearer %s" % key
        if data:
            headers["Content-Type"] = headers.get("Content-Type", "application/json")
            headers["Content-Length"] = str(len(data))

        try:
            conn = self._connect()
            conn.request(self.command, self.path, body=data or None, headers=headers)
            response = conn.getresponse()
            self.send_response(response.status)
            for header_name, value in response.getheaders():
                if header_name.lower() not in HOP and header_name.lower() != "content-length":
                    self.send_header(header_name, value)
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            if self.command != "HEAD":
                while True:
                    chunk = response.read(65536)
                    if not chunk:
                        break
                    self.wfile.write(b"%x\r\n" % len(chunk))
                    self.wfile.write(chunk)
                    self.wfile.write(b"\r\n")
                    self.wfile.flush()
                self.wfile.write(b"0\r\n\r\n")
                self.wfile.flush()
            conn.close()
        except OSError as error:
            message = json.dumps(
                {
                    "error": {
                        "message": "muse-spark-proxy: backend unreachable at %s: %s"
                        % (self.backend, error)
                    }
                }
            ).encode()
            self._send_bytes(502, message, "application/json")

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0].rstrip("/")
        if path in {"/health", "/v1/health"}:
            self._send_bytes(200, b'{"ok":true}', "application/json")
            return
        if path in {"/v1/models", "/models"}:
            self._send_bytes(200, models_payload(), "application/json")
            return
        self._proxy()

    def do_HEAD(self) -> None:  # noqa: N802
        self.do_GET()

    def do_POST(self) -> None:  # noqa: N802
        self._proxy()

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self.send_header("Allow", "GET, HEAD, POST, OPTIONS")
        self.end_headers()


def main() -> None:
    load_meta_env()
    backend = os.environ.get("MUSE_SPARK_BACKEND", DEFAULT_BACKEND).rstrip("/")
    backend_url = urlparse(backend)
    listen_host = os.environ.get("MUSE_SPARK_LISTEN_HOST", DEFAULT_HOST)
    listen_port = int(os.environ.get("MUSE_SPARK_LISTEN_PORT", DEFAULT_PORT))
    Handler.backend = backend
    Handler.backend_host = backend_url.hostname or "api.meta.ai"
    Handler.backend_scheme = backend_url.scheme or "https"
    Handler.backend_port = backend_url.port or (
        443 if Handler.backend_scheme == "https" else 80
    )
    server = ThreadingHTTPServer((listen_host, listen_port), Handler)
    sys.stderr.write(
        "muse-spark-proxy listening on http://%s:%s -> %s (%s)\n"
        % (listen_host, listen_port, backend, MODEL)
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
