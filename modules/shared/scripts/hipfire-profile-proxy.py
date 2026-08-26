#!/usr/bin/env python3
"""OpenAI-compat router in front of hipfire serve.

Clients address stable profile ids (forge, anvil, feather). This process rewrites
them to the current backend model tag and fills default thinking/effort
when the client omitted those fields. Customization still wins: an
explicit reasoning_effort or enable_thinking from Pi/Grok/Hermes is kept.
"""
from __future__ import annotations

import http.client
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import urlparse


def load_config() -> dict[str, Any]:
    raw = os.environ.get("HIPFIRE_PROFILES_JSON", "")
    if not raw:
        raise SystemExit("HIPFIRE_PROFILES_JSON is required")
    return json.loads(raw)


CFG = load_config()
BACKEND = str(CFG.get("backend", "http://127.0.0.1:11435")).rstrip("/")
BACKEND_MODEL = str(CFG["backend_model"])
PROFILES: dict[str, Any] = CFG.get("profiles") or {}
LISTEN_HOST = os.environ.get("HIPFIRE_PROFILE_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("HIPFIRE_PROFILE_PORT", CFG.get("listen_port", 8080)))
BACKEND_URL = urlparse(BACKEND)
BACKEND_HOST = BACKEND_URL.hostname or "127.0.0.1"
BACKEND_PORT = BACKEND_URL.port or (443 if BACKEND_URL.scheme == "https" else 80)


def apply_profile(body: dict[str, Any]) -> dict[str, Any]:
    model = body.get("model")
    if not isinstance(model, str) or model not in PROFILES:
        return body
    profile = PROFILES[model]
    body["model"] = BACKEND_MODEL
    defaults = profile.get("defaults") or {}
    for key, value in defaults.items():
        if key == "chat_template_kwargs":
            existing = body.get("chat_template_kwargs")
            merged = dict(value) if isinstance(value, dict) else {}
            if isinstance(existing, dict):
                merged.update(existing)
            body["chat_template_kwargs"] = merged
        elif key not in body:
            body[key] = value
    return body


def models_payload() -> bytes:
    data = []
    for profile_id, profile in PROFILES.items():
        data.append(
            {
                "id": profile_id,
                "object": "model",
                "owned_by": "hipfire-profiles",
                "name": profile.get("display_name", profile_id),
                "description": profile.get("description", ""),
                "context_window": profile.get("context_window"),
            }
        )
    data.append(
        {
            "id": BACKEND_MODEL,
            "object": "model",
            "owned_by": "hipfire",
        }
    )
    return json.dumps({"object": "list", "data": data}).encode()


def is_completion_path(path: str) -> bool:
    clean = path.split("?", 1)[0].rstrip("/")
    return clean.endswith("/chat/completions") or clean.endswith("/completions")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

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
                data = json.dumps(apply_profile(body)).encode()

        headers = {
            key: value
            for key, value in self.headers.items()
            if key.lower() not in {"host", "content-length"}
        }
        if data:
            headers["Content-Type"] = headers.get("Content-Type", "application/json")
            headers["Content-Length"] = str(len(data))

        try:
            conn = http.client.HTTPConnection(BACKEND_HOST, BACKEND_PORT, timeout=3600)
            conn.request(self.command, self.path, body=data or None, headers=headers)
            response = conn.getresponse()
            self.send_response(response.status)
            hop = {"connection", "transfer-encoding"}
            for key, value in response.getheaders():
                if key.lower() not in hop:
                    self.send_header(key, value)
            # http.client already dechunks. Re-chunk so keep-alive clients
            # (Pi streaming) see a finished body instead of hanging.
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
                        "message": f"hipfire backend unreachable at {BACKEND}: {error}"
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
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    sys.stderr.write(
        "hipfire-profile-proxy listening on http://%s:%s -> %s (%s)\n"
        % (LISTEN_HOST, LISTEN_PORT, BACKEND, ", ".join(PROFILES))
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
