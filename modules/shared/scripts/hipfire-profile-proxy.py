#!/usr/bin/env python3
"""OpenAI-compat router in front of hipfire serve.

Lanes (forge/anvil/feather) are stable agent names. They rewrite to a
backend tag and fill thinking/effort/speculation when the client omitted
those fields. Explicit client fields win.

Model ids:
  forge / anvil / feather   lanes on the catalog default backend
  fuse                      non-thinking lane on the Fuse-2 MoE backend
  forge/fuse                UNSUPPORTED (forge thinking breaks Fuse); use fuse
  qwen38                    raw backend — no lane defaults

Unknown ids return HTTP 400. Prompts that cannot fit `max_seq` return HTTP 413.
If the prompt fits, `max_tokens` is clamped to the remaining GPU room instead
of 413 (chars/2 plus a 16k gen cap against the advertised 49k window was
tripping Pi at ~57% of forge). Direct hipfire :11435 is loopback-only.
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


class RequestTooLarge(ValueError):
    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.message = message


def load_config() -> dict[str, Any]:
    raw = os.environ.get("HIPFIRE_PROFILES_JSON", "")
    if not raw:
        raise SystemExit("HIPFIRE_PROFILES_JSON is required")
    return json.loads(raw)


def backends_of(cfg: dict[str, Any]) -> dict[str, Any]:
    return dict(cfg.get("backends") or {})


def lanes_of(cfg: dict[str, Any]) -> dict[str, Any]:
    return dict(cfg.get("profiles") or cfg.get("lanes") or {})


THINK_ANSWER_ROOM = 512


def backend_available(backend: Any) -> bool:
    if not isinstance(backend, dict):
        return False
    return backend.get("available", True) is not False


def default_backend_id(cfg: dict[str, Any]) -> str:
    backends = backends_of(cfg)
    requested = cfg.get("default_backend")
    if isinstance(requested, str) and requested in backends and backend_available(
        backends[requested]
    ):
        return requested
    for backend_id, backend in backends.items():
        if backend_available(backend):
            return backend_id
    if len(backends) == 1:
        return next(iter(backends))
    return "qwen38"


def lane_backend_id(cfg: dict[str, Any], lane: dict[str, Any] | None) -> str:
    """Bare lane id uses an optional pin, else the catalog default backend."""
    pinned = lane.get("backend") if isinstance(lane, dict) else None
    if isinstance(pinned, str) and pinned:
        backends = backends_of(cfg)
        if pinned in backends:
            return pinned
        found = lookup_backend(cfg, pinned)
        if found is not None:
            return found[0]
    return default_backend_id(cfg)


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
    # Always pin the selector. Omitting "off" left AR lanes on a resident
    # DFlash draft (models.toml dflash=auto) after Anvil/Feather.
    if "speculation" not in body:
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


def advertised_context(
    lane: dict[str, Any] | None, backend: dict[str, Any] | None
) -> int | None:
    """Pi/Grok compaction window. Composites follow the backend (weights),
    not min(lane, backend) — forge's 49k Qwen-safe window must not shrink Ornith."""
    seq = _as_int(backend.get("max_seq")) if isinstance(backend, dict) else None
    win = None
    if isinstance(backend, dict):
        win = _as_int(backend.get("context_window"))
    if win is None and isinstance(lane, dict):
        win = _as_int(lane.get("context_window"))
    if win is None:
        return seq
    if seq is not None:
        return min(win, seq)
    return win


def _as_int(value: Any) -> int | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    return None


def estimate_prompt_tokens(body: dict[str, Any]) -> int:
    chars = 0
    prompt = body.get("prompt")
    if isinstance(prompt, str):
        chars += len(prompt)
    messages = body.get("messages")
    if isinstance(messages, list):
        for message in messages:
            if not isinstance(message, dict):
                continue
            content = message.get("content")
            if isinstance(content, str):
                chars += len(content)
            elif isinstance(content, list):
                for part in content:
                    if isinstance(part, dict) and isinstance(part.get("text"), str):
                        chars += len(part["text"])
    return max((chars + 1) // 2, 1)


def enforce_budgets(
    body: dict[str, Any],
    lane: dict[str, Any] | None,
    backend: dict[str, Any] | None,
) -> None:
    """Clamp generation/think caps and refuse prompts that cannot fit the window."""
    window = None
    max_tokens_cap = None
    think_cap = None
    max_seq = None
    if isinstance(lane, dict):
        window = _as_int(lane.get("context_window"))
        max_tokens_cap = _as_int(lane.get("max_tokens"))
        defaults = lane.get("defaults") if isinstance(lane.get("defaults"), dict) else {}
        think_cap = _as_int(defaults.get("max_think_tokens")) or _as_int(
            lane.get("max_think_tokens")
        )
    if isinstance(backend, dict):
        backend_window = _as_int(backend.get("context_window"))
        backend_max = _as_int(backend.get("max_tokens"))
        max_seq = _as_int(backend.get("max_seq"))
        if window is None:
            window = backend_window
        elif backend_window is not None:
            window = min(window, backend_window)
        if max_tokens_cap is None:
            max_tokens_cap = backend_max
        elif backend_max is not None:
            max_tokens_cap = min(max_tokens_cap, backend_max)
    if max_tokens_cap is not None:
        for key in ("max_tokens", "max_completion_tokens"):
            current = _as_int(body.get(key))
            if current is not None:
                body[key] = min(current, max_tokens_cap)
        if "max_tokens" not in body and "max_completion_tokens" not in body:
            body["max_tokens"] = max_tokens_cap
    if think_cap is not None:
        current = _as_int(body.get("max_think_tokens"))
        body["max_think_tokens"] = think_cap if current is None else min(current, think_cap)
    thinking_on = True
    kwargs = body.get("chat_template_kwargs")
    if isinstance(kwargs, dict) and "enable_thinking" in kwargs:
        thinking_on = bool(kwargs["enable_thinking"])
    elif "enable_thinking" in body:
        thinking_on = bool(body["enable_thinking"])
    elif think_cap is None:
        thinking_on = False
    if thinking_on and think_cap is not None:
        floor = think_cap + THINK_ANSWER_ROOM
        if max_tokens_cap is not None:
            floor = min(floor, max_tokens_cap)
        for key in ("max_tokens", "max_completion_tokens"):
            current = _as_int(body.get(key))
            if current is not None and current < floor:
                body[key] = floor
        if "max_tokens" not in body and "max_completion_tokens" not in body:
            body["max_tokens"] = floor
    max_tokens = (
        _as_int(body.get("max_tokens"))
        or _as_int(body.get("max_completion_tokens"))
        or max_tokens_cap
        or 0
    )
    # Advertised `context_window` is the Pi/Grok compaction target, not the GPU
    # allocation. hipfire fail-closes on `max_seq`. Mixing the two here 413'd
    # forge around 57% of 49k: chars/2 overestimates Qwen BPE, then we reserved
    # the full 16k gen cap against that smaller window.
    hard_ceiling = max_seq or window
    if hard_ceiling is None:
        return
    prompt_tokens = estimate_prompt_tokens(body)
    if prompt_tokens > hard_ceiling:
        raise RequestTooLarge(
            "prompt (~%s tokens) exceeds max_seq (%s)" % (prompt_tokens, hard_ceiling)
        )
    room = hard_ceiling - prompt_tokens - 1
    if room < 1:
        raise RequestTooLarge(
            "prompt (~%s tokens) leaves no room under max_seq (%s)"
            % (prompt_tokens, hard_ceiling)
        )
    if max_tokens > room:
        sys.stderr.write(
            "hipfire-profile-proxy: clamping max_tokens %s -> %s "
            "(prompt~%s max_seq=%s)\n"
            % (max_tokens, room, prompt_tokens, hard_ceiling)
        )
        for key in ("max_tokens", "max_completion_tokens"):
            if key in body:
                body[key] = room
        if "max_tokens" not in body and "max_completion_tokens" not in body:
            body["max_tokens"] = room


def apply_request(cfg: dict[str, Any], body: dict[str, Any]) -> dict[str, Any]:
    model = body.get("model")
    if not isinstance(model, str) or not model:
        raise UnknownModel("")
    lanes = lanes_of(cfg)
    backends = backends_of(cfg)
    lane: dict[str, Any] | None = None
    backend: dict[str, Any] | None = None

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
        lane = lanes[lane_id]
        apply_lane_defaults(body, lane, backend)
        enforce_budgets(body, lane, backend)
        return body

    if model in lanes:
        lane = lanes[model]
        backend_id = lane_backend_id(cfg, lane)
        backend = backends.get(backend_id)
        if not isinstance(backend, dict):
            legacy = cfg.get("backend_model")
            if isinstance(legacy, str):
                body["model"] = legacy
                apply_lane_defaults(
                    body, lane, {"speculation": ["off", "dflash", "mtp"]}
                )
                enforce_budgets(body, lane, None)
                return body
            raise UnknownModel(model)
        body["model"] = str(backend.get("tag") or backend_id)
        apply_lane_defaults(body, lane, backend)
        enforce_budgets(body, lane, backend)
        return body

    found = lookup_backend(cfg, model)
    if found is not None:
        backend_id, backend = found
        body["model"] = str(backend.get("tag") or model)
        enforce_budgets(body, None, backend)
        return body

    raise UnknownModel(model)


def catalog_ids(cfg: dict[str, Any]) -> list[dict[str, Any]]:
    data: list[dict[str, Any]] = []
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
        if not backend_available(backend):
            continue
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
        skip_id = lane_backend_id(cfg, lane)
        for backend_id, backend in backends_of(cfg).items():
            if backend_id == skip_id or not backend_available(backend):
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
                    "context_window": advertised_context(lane, backend),
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
                                    "a backend (qwen38), or lane/backend"
                                    % error.model
                                )
                            }
                        }
                    ).encode()
                    self._send_bytes(400, message, "application/json")
                    return
                except RequestTooLarge as error:
                    message = json.dumps(
                        {"error": {"message": error.message}}
                    ).encode()
                    self._send_bytes(413, message, "application/json")
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
