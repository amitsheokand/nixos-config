#!/usr/bin/env python3
"""Merge forge/anvil/feather aliases into ~/.hermes/config.yaml without changing the default provider."""
from __future__ import annotations

import os
import sys

import yaml

HOME = os.path.expanduser("~")
CONFIG_PATH = os.path.join(HOME, ".hermes", "config.yaml")
BASE_URL = os.environ.get("AI_BASE_URL", "http://127.0.0.1:8080/v1")


def alias_entry(model: str) -> dict:
    return {
        "model": model,
        "provider": "custom",
        "base_url": BASE_URL,
        "api_key": "local",
    }


def main() -> int:
    aliases = {
        "forge": alias_entry("forge"),
        "anvil": alias_entry("anvil"),
        "feather": alias_entry("feather"),
    };
    os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    data: dict
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
        if name not in existing:
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
    print("hermes-merge-hipfire-aliases: added forge/anvil/feather (default provider unchanged)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
