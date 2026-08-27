#!/usr/bin/env python3
"""Merge hipfire OpenAI-compatible models into ~/.config/zed/settings.json.

Does not change agent.default_model, theme, or other user keys.
"""
from __future__ import annotations

import json
import os
import re
import sys

HOME = os.path.expanduser("~")
CONFIG_PATH = os.path.join(HOME, ".config", "zed", "settings.json")
BASE_URL = os.environ.get("AI_BASE_URL", "http://127.0.0.1:8080/v1")


def load_catalog() -> dict:
    raw = os.environ.get("HIPFIRE_PROFILES_JSON", "")
    return json.loads(raw) if raw else {}


def available_models(cfg: dict) -> list[dict]:
    models = []
    lanes = cfg.get("profiles") or {}
    backends = cfg.get("backends") or {}
    default_backend = cfg.get("default_backend") or "ornith"
    for lane_id, lane in lanes.items():
        models.append(
            {
                "name": lane_id,
                "display_name": lane.get("display_name", lane_id),
                "max_tokens": lane.get("context_window") or 49152,
                "max_output_tokens": lane.get("max_tokens") or 16384,
                **(
                    {"reasoning_effort": lane.get("defaults", {}).get("reasoning_effort")}
                    if (lane.get("defaults") or {}).get("reasoning_effort")
                    else {}
                ),
            }
        )
    for backend_id, backend in backends.items():
        models.append(
            {
                "name": backend_id,
                "display_name": backend.get("display_name", backend_id),
                "max_tokens": backend.get("context_window") or 49152,
                "max_output_tokens": backend.get("max_tokens") or 16384,
            }
        )
    for lane_id, lane in lanes.items():
        for backend_id, backend in backends.items():
            if backend_id == default_backend:
                continue
            models.append(
                {
                    "name": f"{lane_id}/{backend_id}",
                    "display_name": "%s (%s)"
                    % (
                        lane.get("display_name", lane_id),
                        backend.get("display_name", backend_id),
                    ),
                    "max_tokens": lane.get("context_window")
                    or backend.get("context_window")
                    or 49152,
                    "max_output_tokens": lane.get("max_tokens") or 16384,
                }
            )
    return models


def strip_jsonc(text: str) -> str:
    # Zed settings allow // comments and trailing commas.
    lines = []
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("//"):
            continue
        lines.append(line)
    cleaned = "\n".join(lines)
    return re.sub(r",(\s*[}\]])", r"\1", cleaned)


def main() -> int:
    cfg = load_catalog()
    models = available_models(cfg)
    if not models:
        return 0
    os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, encoding="utf-8") as handle:
            raw = handle.read()
        try:
            data = json.loads(strip_jsonc(raw))
        except json.JSONDecodeError:
            print("zed-merge-hipfire: settings.json is not JSON; skipped", file=sys.stderr)
            return 0
        if not isinstance(data, dict):
            return 0
    else:
        data = {}

    language_models = data.get("language_models")
    if not isinstance(language_models, dict):
        language_models = {}
    openai_compatible = language_models.get("openai_compatible")
    if not isinstance(openai_compatible, dict):
        openai_compatible = {}
    hipfire = {
        "api_url": BASE_URL,
        "available_models": models,
    }
    if openai_compatible.get("hipfire") == hipfire:
        return 0
    openai_compatible["hipfire"] = hipfire
    language_models["openai_compatible"] = openai_compatible
    data["language_models"] = language_models

    tmp = CONFIG_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")
    os.replace(tmp, CONFIG_PATH)
    print("zed-merge-hipfire: wrote language_models.openai_compatible.hipfire")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
