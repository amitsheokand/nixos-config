#!/usr/bin/env python3
"""Merge hipfire lanes into ~/.continue/config.yaml without replacing other models."""
from __future__ import annotations

import json
import os
import sys

import yaml

HOME = os.path.expanduser("~")
CONFIG_PATH = os.path.join(HOME, ".continue", "config.yaml")
BASE_URL = os.environ.get("AI_BASE_URL", "http://127.0.0.1:8080/v1")


def load_catalog() -> dict:
    raw = os.environ.get("HIPFIRE_PROFILES_JSON", "")
    return json.loads(raw) if raw else {}


def hipfire_models(cfg: dict) -> list[dict]:
    models = []
    lanes = cfg.get("profiles") or {}
    backends = cfg.get("backends") or {}
    default_backend = cfg.get("default_backend") or "qwen38"
    ids = list(lanes) + [
        backend_id
        for backend_id, backend in backends.items()
        if backend.get("available", True) is not False
    ]
    for lane_id in lanes:
        for backend_id, backend in backends.items():
            if backend_id != default_backend and backend.get("available", True) is not False:
                ids.append(f"{lane_id}/{backend_id}")
    seen = set()
    for model_id in ids:
        if model_id in seen:
            continue
        seen.add(model_id)
        title = model_id
        if model_id in lanes:
            title = (lanes[model_id] or {}).get("display_name", model_id)
        elif model_id in backends:
            title = (backends[model_id] or {}).get("display_name", model_id)
        models.append(
            {
                "name": title,
                "provider": "openai",
                "model": model_id,
                "apiBase": BASE_URL,
                "apiKey": "local",
            }
        )
    return models


def main() -> int:
    cfg = load_catalog()
    incoming = hipfire_models(cfg)
    if not incoming:
        return 0
    os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, encoding="utf-8") as handle:
            loaded = yaml.safe_load(handle) or {}
        if not isinstance(loaded, dict):
            print("continue-merge-hipfire: config.yaml is not a mapping; skipped", file=sys.stderr)
            return 0
        data = loaded
    else:
        data = {"name": "local", "version": "1.0.0", "schema": "v1", "models": []}

    existing = data.get("models")
    if not isinstance(existing, list):
        existing = []
    by_model = {
        item.get("model"): item
        for item in existing
        if isinstance(item, dict) and item.get("model")
    }
    changed = False
    for item in incoming:
        current = by_model.get(item["model"])
        if current != item:
            by_model[item["model"]] = item
            changed = True
    if not changed and existing:
        return 0
    kept = [
        item
        for item in existing
        if not (isinstance(item, dict) and item.get("model") in {m["model"] for m in incoming})
    ]
    data["models"] = incoming + kept
    tmp = CONFIG_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        yaml.safe_dump(data, handle, sort_keys=False, allow_unicode=True)
    os.replace(tmp, CONFIG_PATH)
    os.chmod(CONFIG_PATH, 0o600)
    print("continue-merge-hipfire: refreshed hipfire models")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
