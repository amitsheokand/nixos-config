#!/usr/bin/env python3
"""OpenAI-compat router in front of hipfire serve.

Lanes (forge/anvil/feather) are stable agent names. They rewrite to a
backend tag and fill thinking/effort/speculation when the client omitted
those fields. Explicit client fields win.

Model ids:
  forge                 lane on the default backend
  forge/qwen38          lane on an explicit backend (weight swap)
  ornith / qwen38       backend ids — no lane defaults
  ornith-1.5:35b-a3b    hipfire tags listed as backend aliases

Unknown ids return HTTP 400. Direct hipfire :11435 remains available for
operator filenames.
"""
from __future__ import annotations

import http.client
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import urlparse


class UnknownModel(ValueError):
    def __init__(self, model: str) -> None:
        super().__init__(model)
        self.model = model


def load_config() -> dict[str, Any]:
    raw = os.environ.get("HIPFIRE_PROFILES_JSON", "")
    if not raw:
        raise SystemExit("HIPFIRE_PROFILES_JSON is required")
    return json.loads(raw)


def backends_of(cfg: dict[str, Any]) -> dict[str, Any]:
    return dict(cfg.get("backends") or {})


def lanes_of(cfg: dict[str, Any]) -> dict[str, Any]:
    return dict(cfg.get("profiles") or cfg.get("lanes") or {})


def default_backend_id(cfg: dict[str, Any]) -> str:
    if cfg.get("default_backend"):
        return str(cfg["default_backend"])
    backends = backends_of(cfg)
    if len(backends) == 1:
        return next(iter(backends))
    return "ornith"


def lookup_backend(cfg: dict[str, Any], model: str) -> tuple[str, dict[str, Any]] | None:
    for backend_id, backend in backends_of(cfg).items():
        names = [backend_id, str(backend.get("tag") or "")]
        names.extend(str(alias) for alias in (backend.get("aliases") or []))
        if model in names:
            return backend_id, backend
    return None


def resolve_speculation(policy: Any, backend: dict[str, Any]) -> str:
    allowed = [str(item) for item in (backend.get("speculation") or ["off"])]
    if not allowed:
        allowed = ["off"]
    text = "off" if policy is None else str(policy)
    if text == "dflash-if-capable":
        if "dflash" in allowed:
            return "dflash"
        if "mtp" in allowed:
            return "mtp"
        return "off"
    if text == "mtp-if-capable":
        return "mtp" if "mtp" in allowed else "off"
    if text in allowed:
        return text
    return "off"


def apply_lane_defaults(
    body: dict[str, Any], lane: dict[str, Any], backend: dict[str, Any]
) -> None:
    defaults = dict(lane.get("defaults") or {})
    spec = resolve_speculation(
        defaults.pop("speculation", lane.get("speculation")), backend
    )
    if spec and "speculation" not in body:
        body["speculation"] = spec
    for key, value in defaults.items():
        if key == "chat_template_kwargs":
            existing = body.get("chat_template_kwargs")
            merged = dict(value) if isinstance(value, dict) else {}
            if isinstance(existing, dict):
                merged.update(existing)
            body["chat_template_kwargs"] = merged
        elif key not in body:
            body[key] = value


def split_composite(model: str) -> tuple[str, str] | None:
    if "/" not in model:
        return None
    lane_id, backend_id = model.split("/", 1)
    if not lane_id or not backend_id or "/" in backend_id:
        return None
    return lane_id, backend_id


def apply_request(cfg: dict[str, Any], body: dict[str, Any]) -> dict[str, Any]:
    model = body.get("model")
    if not isinstance(model, str) or not model:
        raise UnknownModel("")
    lanes = lanes_of(cfg)
    backends = backends_of(cfg)

    composite = split_composite(model)
    if composite is not None:
        lane_id, backend_id = composite
        if lane_id not in lanes:
            raise UnknownModel(model)
        backend = backends.get(backend_id)
        if not isinstance(backend, dict):
            found = lookup_backend(cfg, backend_id)
            if found is None:
                raise UnknownModel(model)
            backend_id, backend = found
        body["model"] = str(backend.get("tag") or backend_id)
        apply_lane_defaults(body, lanes[lane_id], backend)
        return body

    if model in lanes:
        backend_id = default_backend_id(cfg)
        backend = backends.get(backend_id)
        if not isinstance(backend, dict):
            legacy = cfg.get("backend_model")
            if isinstance(legacy, str):
                body["model"] = legacy
                apply_lane_defaults(
                    body, lanes[model], {"speculation": ["off", "dflash", "mtp"]}
                )
                return body
            raise UnknownModel(model)
        body["model"] = str(backend.get("tag") or backend_id)
        apply_lane_defaults(body, lanes[model], backend)
        return body

    found = lookup_backend(cfg, model)
    if found is not None:
        backend_id, backend = found
        body["model"] = str(backend.get("tag") or model)
        return body

    raise UnknownModel(model)


def catalog_ids(cfg: dict[str, Any]) -> list[dict[str, Any]]:
    data: list[dict[str, Any]] = []
    default_id = default_backend_id(cfg)
    for lane_id, lane in lanes_of(cfg).items():
        data.append(
            {
                "id": lane_id,
                "object": "model",
                "owned_by": "hipfire-lanes",
                "name": lane.get("display_name", lane_id),
                "description": lane.get("description", ""),
                "context_window": lane.get("context_window"),
            }
        )
    for backend_id, backend in backends_of(cfg).items():
        data.append(
            {
                "id": backend_id,
                "object": "model",
                "owned_by": "hipfire",
                "name": backend.get("display_name", backend_id),
                "description": backend.get("description", ""),
                "context_window": backend.get("context_window"),
            }
        )
    for lane_id, lane in lanes_of(cfg).items():
        for backend_id, backend in backends_of(cfg).items():
            if backend_id == default_id:
                continue
            composite = f"{lane_id}/{backend_id}"
            data.append(
                {
                    "id": composite,
                    "object": "model",
                    "owned_by": "hipfire-lanes",
                    "name": "%s (%s)"
                    % (
                        lane.get("display_name", lane_id),
                        backend.get("display_name", backend_id),
                    ),
                    "description": "Lane %s on backend %s." % (lane_id, backend_id),
                    "context_window": lane.get("context_window")
                    or backend.get("context_window"),
                }
            )
    if not backends_of(cfg) and cfg.get("backend_model"):
        data.append(
            {
                "id": cfg["backend_model"],
                "object": "model",
                "owned_by": "hipfire",
            }
        )
    return data


def models_payload(cfg: dict[str, Any]) -> bytes:
    return json.dumps({"object": "list", "data": catalog_ids(cfg)}).encode()


def is_completion_path(path: str) -> bool:
    clean = path.split("?", 1)[0].rstrip("/")
    return clean.endswith("/chat/completions") or clean.endswith("/completions")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    cfg: dict[str, Any] = {}
    backend_host = "127.0.0.1"
    backend_port = 11435
    backend = "http://127.0.0.1:11435"

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
                try:
                    data = json.dumps(apply_request(self.cfg, body)).encode()
                except UnknownModel as error:
                    message = json.dumps(
                        {
                            "error": {
                                "message": (
                                    "unknown model %r; use a lane (forge/anvil/feather), "
                                    "a backend (ornith/qwen38), or lane/backend"
                                    % error.model
                                )
                            }
                        }
                    ).encode()
                    self._send_bytes(400, message, "application/json")
                    return

        headers = {
            key: value
            for key, value in self.headers.items()
            if key.lower() not in {"host", "content-length"}
        }
        if data:
            headers["Content-Type"] = headers.get("Content-Type", "application/json")
            headers["Content-Length"] = str(len(data))

        try:
            conn = http.client.HTTPConnection(
                self.backend_host, self.backend_port, timeout=3600
            )
            conn.request(self.command, self.path, body=data or None, headers=headers)
            response = conn.getresponse()
            self.send_response(response.status)
            hop = {"connection", "transfer-encoding"}
            for key, value in response.getheaders():
                if key.lower() not in hop:
                    self.send_header(key, value)
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
                        "message": f"hipfire backend unreachable at {self.backend}: {error}"
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
            self._send_bytes(200, models_payload(self.cfg), "application/json")
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
    cfg = load_config()
    backend = str(cfg.get("backend", "http://127.0.0.1:11435")).rstrip("/")
    backend_url = urlparse(backend)
    listen_host = os.environ.get("HIPFIRE_PROFILE_HOST", "127.0.0.1")
    listen_port = int(os.environ.get("HIPFIRE_PROFILE_PORT", cfg.get("listen_port", 8080)))
    Handler.cfg = cfg
    Handler.backend = backend
    Handler.backend_host = backend_url.hostname or "127.0.0.1"
    Handler.backend_port = backend_url.port or (443 if backend_url.scheme == "https" else 80)
    server = ThreadingHTTPServer((listen_host, listen_port), Handler)
    names = [item["id"] for item in catalog_ids(cfg)]
    sys.stderr.write(
        "hipfire-profile-proxy listening on http://%s:%s -> %s (%s)\n"
        % (listen_host, listen_port, backend, ", ".join(names))
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
