#!/usr/bin/env python3
"""Merge catalog lanes/backends into ~/.hermes/config.yaml.

Does not change the default provider. Catalog JSON is HIPFIRE_PROFILES_JSON.
"""
from __future__ import annotations

import json
import os
import sys

import yaml

HOME = os.path.expanduser("~")
CONFIG_PATH = os.path.join(HOME, ".hermes", "config.yaml")
BASE_URL = os.environ.get("AI_BASE_URL", "http://127.0.0.1:8080/v1")


def load_catalog() -> dict:
    raw = os.environ.get("HIPFIRE_PROFILES_JSON", "")
    if not raw:
        return {
            "default_backend": "ornith",
            "backends": {},
            "profiles": {
                "forge": {"display_name": "Forge"},
                "anvil": {"display_name": "Anvil"},
                "feather": {"display_name": "Feather"},
            },
        }
    return json.loads(raw)


def extra_body_from_lane(lane: dict) -> dict:
    defaults = dict(lane.get("defaults") or {})
    extra = {}
    if "reasoning_effort" in defaults:
        extra["reasoning_effort"] = defaults["reasoning_effort"]
    if "max_think_tokens" in defaults:
        extra["max_think_tokens"] = defaults["max_think_tokens"]
    if "max_tokens" in defaults:
        extra["max_tokens"] = defaults["max_tokens"]
    if "chat_template_kwargs" in defaults:
        extra["chat_template_kwargs"] = defaults["chat_template_kwargs"]
    if "temperature" in defaults:
        extra["temperature"] = defaults["temperature"]
    if "presence_penalty" in defaults:
        extra["presence_penalty"] = defaults["presence_penalty"]
    spec = defaults.get("speculation", lane.get("speculation"))
    if spec and spec not in {"dflash-if-capable", "mtp-if-capable"}:
        extra["speculation"] = spec
    return extra


def alias_entry(model: str, extra_body: dict | None = None) -> dict:
    entry = {
        "model": model,
        "provider": "custom",
        "base_url": BASE_URL,
        "api_key": "local",
    }
    if extra_body:
        entry["extra_body"] = extra_body
    return entry


def catalog_aliases(cfg: dict) -> dict[str, dict]:
    aliases: dict[str, dict] = {}
    lanes = cfg.get("profiles") or cfg.get("lanes") or {}
    backends = cfg.get("backends") or {}
    default_backend = cfg.get("default_backend") or "ornith"
    for lane_id, lane in lanes.items():
        aliases[lane_id] = alias_entry(lane_id, extra_body_from_lane(lane))
    for backend_id in backends:
        aliases[backend_id] = alias_entry(backend_id)
    for lane_id, lane in lanes.items():
        for backend_id in backends:
            if backend_id == default_backend:
                continue
            name = f"{lane_id}/{backend_id}"
            aliases[name] = alias_entry(name, extra_body_from_lane(lane))
    return aliases


def main() -> int:
    aliases = catalog_aliases(load_catalog())
    os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, encoding="utf-8") as handle:
            loaded = yaml.safe_load(handle) or {}
        if not isinstance(loaded, dict):
            print("hermes-merge-hipfire-aliases: config.yaml is not a mapping; skipped", file=sys.stderr)
            return 0
        data = loaded
    else:
        data = {}

    existing = data.get("model_aliases")
    if not isinstance(existing, dict):
        existing = {}
    changed = False
    for name, entry in aliases.items():
        if existing.get(name) != entry:
            existing[name] = entry
            changed = True
    if not changed:
        return 0
    data["model_aliases"] = existing
    tmp = CONFIG_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        yaml.safe_dump(data, handle, sort_keys=False, allow_unicode=True)
    os.replace(tmp, CONFIG_PATH)
    os.chmod(CONFIG_PATH, 0o600)
    print("hermes-merge-hipfire-aliases: refreshed %s" % ", ".join(aliases))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
