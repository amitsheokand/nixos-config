#!/usr/bin/env python3
"""Merge Meta Model API (Muse Spark) into OpenCode, Hermes, and Zed.

Does not write secrets into git-managed files. Reads MODEL_API_KEY /
META_API_KEY from the environment (zsh sources ~/.config/meta.env).
OpenCode stores the key via /connect; we only register the provider
against api.meta.ai (Responses). Hermes / Zed Chat Completions go
through the local muse-spark-proxy (:8082) so Spark's reused call_0
ids do not 400.
"""
from __future__ import annotations

import json
import os
import re
import stat
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None  # type: ignore

HOME = Path.home()
OPENCODE = HOME / ".config" / "opencode" / "opencode.json"
HERMES = HOME / ".hermes" / "config.yaml"
ZED = HOME / ".config" / "zed" / "settings.json"
META_URL = "https://api.meta.ai/v1"
PROXY_URL = os.environ.get("MUSE_SPARK_PROXY_URL", "http://127.0.0.1:8082/v1")
MODEL = "muse-spark-1.2"

PROVIDER = {
    "name": "Meta Model API",
    "npm": "@ai-sdk/openai",
    "options": {"baseURL": META_URL},
    "models": {
        MODEL: {
            "name": MODEL,
            "reasoning": True,
            "limit": {"context": 1048576, "output": 131072},
            "modalities": {
                "input": ["text", "image", "pdf", "video"],
                "output": ["text"],
            },
            "options": {
                "reasoningEffort": "high",
                "reasoningSummary": "auto",
                "include": ["reasoning.encrypted_content"],
            },
        }
    },
}

ZED_META = {
    "api_url": PROXY_URL,
    "available_models": [
        {
            "name": MODEL,
            "display_name": "Muse Spark 1.2",
            "max_tokens": 1048576,
            "max_output_tokens": 131072,
            "reasoning_effort": "high",
            "capabilities": {
                "tools": True,
                "images": True,
                "parallel_tool_calls": True,
            },
        }
    ],
}


def api_key() -> str:
    return (
        os.environ.get("MODEL_API_KEY")
        or os.environ.get("META_API_KEY")
        or "$MODEL_API_KEY"
    )


def strip_jsonc(text: str) -> str:
    lines = []
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("//"):
            continue
        lines.append(line)
    cleaned = "\n".join(lines)
    return re.sub(r",(\s*[}\]])", r"\1", cleaned)


def points_at_meta(url: str) -> bool:
    lowered = url.lower()
    return "api.meta.ai" in lowered or ":8082" in lowered


def merge_opencode() -> bool:
    OPENCODE.parent.mkdir(parents=True, exist_ok=True)
    data: dict = {}
    if OPENCODE.is_file():
        try:
            loaded = json.loads(OPENCODE.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            print("muse-spark-merge: opencode.json is not JSON; skipped", file=sys.stderr)
            return False
        if not isinstance(loaded, dict):
            print("muse-spark-merge: opencode.json is not an object; skipped", file=sys.stderr)
            return False
        data = loaded
    providers = data.setdefault("provider", {})
    if not isinstance(providers, dict):
        print("muse-spark-merge: provider is not an object; skipped", file=sys.stderr)
        return False
    if providers.get("meta") == PROVIDER:
        return False
    providers["meta"] = PROVIDER
    tmp = OPENCODE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    tmp.replace(OPENCODE)
    print("muse-spark-merge: registered OpenCode provider meta / %s" % MODEL)
    return True


def merge_hermes() -> bool:
    if yaml is None:
        print("muse-spark-merge: PyYAML missing; Hermes skipped", file=sys.stderr)
        return False
    HERMES.parent.mkdir(parents=True, exist_ok=True)
    data: dict = {}
    if HERMES.is_file():
        with HERMES.open(encoding="utf-8") as handle:
            loaded = yaml.safe_load(handle) or {}
        if not isinstance(loaded, dict):
            print("muse-spark-merge: hermes config.yaml is not a mapping; skipped", file=sys.stderr)
            return False
        data = loaded
    aliases = data.get("model_aliases")
    if not isinstance(aliases, dict):
        aliases = {}
    entry = {
        "model": MODEL,
        "provider": "custom",
        "base_url": PROXY_URL,
        "api_key": api_key(),
    }
    if aliases.get("muse") == entry and aliases.get("muse-spark") == entry:
        return False
    aliases["muse"] = entry
    aliases["muse-spark"] = entry
    data["model_aliases"] = aliases
    tmp = HERMES.with_suffix(".yaml.tmp")
    with tmp.open("w", encoding="utf-8") as handle:
        yaml.safe_dump(data, handle, sort_keys=False, allow_unicode=True)
    tmp.replace(HERMES)
    HERMES.chmod(stat.S_IRUSR | stat.S_IWUSR)
    print("muse-spark-merge: registered Hermes aliases muse / muse-spark -> %s" % PROXY_URL)
    return True


def merge_zed() -> bool:
    ZED.parent.mkdir(parents=True, exist_ok=True)
    if ZED.is_file():
        raw = ZED.read_text(encoding="utf-8")
        try:
            data = json.loads(strip_jsonc(raw))
        except json.JSONDecodeError:
            print("muse-spark-merge: zed settings.json is not JSON; skipped", file=sys.stderr)
            return False
        if not isinstance(data, dict):
            print("muse-spark-merge: zed settings.json is not an object; skipped", file=sys.stderr)
            return False
    else:
        data = {}

    language_models = data.get("language_models")
    if not isinstance(language_models, dict):
        language_models = {}
    openai_compatible = language_models.get("openai_compatible")
    if not isinstance(openai_compatible, dict):
        openai_compatible = {}

    changed = False
    for name, provider in list(openai_compatible.items()):
        if not isinstance(provider, dict):
            continue
        url = str(provider.get("api_url") or "")
        if points_at_meta(url) and url.rstrip("/") != PROXY_URL.rstrip("/"):
            provider = dict(provider)
            provider["api_url"] = PROXY_URL
            openai_compatible[name] = provider
            changed = True

    if openai_compatible.get("meta") != ZED_META:
        openai_compatible["meta"] = ZED_META
        changed = True

    if not changed:
        return False

    language_models["openai_compatible"] = openai_compatible
    data["language_models"] = language_models
    tmp = ZED.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    tmp.replace(ZED)
    print("muse-spark-merge: Zed openai_compatible.meta -> %s" % PROXY_URL)
    return True


def main() -> int:
    merge_opencode()
    merge_hermes()
    merge_zed()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
