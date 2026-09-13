#!/usr/bin/env python3
"""Strip parked hipfire lanes from Continue / Zed / Hermes / Grok user configs.

Registers MiniCPM-V 4.5 at AI_BASE_URL (default http://127.0.0.1:8093/v1).
Does not change cloud defaults (Zed OpenRouter, Hermes Nous, Grok grok-*).
Pi models.json is replaced by Home Manager, not this script.
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

HOME = Path(os.path.expanduser(os.environ.get("HOME", "~")))
DISPLAY_NAME = os.environ.get("MINICPM_V_DISPLAY_NAME", "MiniCPM-V 4.5")
CTX = int(os.environ.get("MINICPM_V_CTX", "8192"))
MAX_TOKENS = int(os.environ.get("MINICPM_V_MAX_TOKENS", "2048"))
DEFAULT_BASE_URL = "http://127.0.0.1:8093/v1"
DEFAULT_MODEL_ID = "minicpm-v-4.5"

HIPFIRE_IDS = {
    "forge",
    "anvil",
    "feather",
    "xt",
    "lfm",
    "qwen38",
    "qwen38-xt",
    "minicpm",
    "fuse",
    "ornith",
}

CONTINUE_PATH = HOME / ".continue" / "config.yaml"
ZED_PATH = HOME / ".config" / "zed" / "settings.json"
HERMES_PATH = HOME / ".hermes" / "config.yaml"
GROK_PATH = HOME / ".grok" / "config.toml"


def is_hipfire_id(model_id: object) -> bool:
    if not isinstance(model_id, str) or not model_id:
        return False
    if model_id in HIPFIRE_IDS:
        return True
    if "/" in model_id:
        return any(part in HIPFIRE_IDS for part in model_id.split("/"))
    return False


def is_hipfire_url(url: object) -> bool:
    if not isinstance(url, str) or not url:
        return False
    lowered = url.lower()
    if ":8093" in lowered or ":8091" in lowered or ":8092" in lowered or ":8082" in lowered:
        return False
    if "ai-mac.local" in lowered:
        return False
    return ":8080" in lowered or ":11435" in lowered


def _normalize_base_url(raw: str) -> str:
    raw = raw.rstrip("/")
    if not raw.endswith("/v1"):
        raw += "/v1"
    return raw


def vl_base_url() -> str:
    # Leftover hipfire env (50-hipfire-p0.conf) must not win over :8093.
    for key in ("MINICPM_V_BASE_URL", "VL_CAPTURE_ENDPOINT", "AI_BASE_URL"):
        val = os.environ.get(key)
        if val and not is_hipfire_url(val):
            return _normalize_base_url(val)
    return DEFAULT_BASE_URL


def vl_model_id() -> str:
    val = os.environ.get("AI_MODEL", DEFAULT_MODEL_ID)
    if is_hipfire_id(val):
        return DEFAULT_MODEL_ID
    return val


BASE_URL = vl_base_url()
MODEL_ID = vl_model_id()


def continue_model() -> dict:
    return {
        "name": DISPLAY_NAME,
        "provider": "openai",
        "model": MODEL_ID,
        "apiBase": BASE_URL,
        "apiKey": "local",
    }


def merge_continue(data: dict) -> dict:
    existing = data.get("models")
    if not isinstance(existing, list):
        existing = []
    kept = []
    for item in existing:
        if not isinstance(item, dict):
            kept.append(item)
            continue
        if is_hipfire_id(item.get("model")) or is_hipfire_url(item.get("apiBase")):
            continue
        if item.get("model") == MODEL_ID:
            continue
        kept.append(item)
    data["models"] = [continue_model()] + kept
    if is_hipfire_id(data.get("selectedModel")):
        data["selectedModel"] = MODEL_ID
    return data


def zed_entry() -> dict:
    return {
        "api_url": BASE_URL,
        "available_models": [
            {
                "name": MODEL_ID,
                "display_name": DISPLAY_NAME,
                "max_tokens": CTX,
                "max_output_tokens": MAX_TOKENS,
                "capabilities": {"images": True, "tools": True},
            }
        ],
    }


def merge_zed(data: dict) -> dict:
    language_models = data.get("language_models")
    if not isinstance(language_models, dict):
        language_models = {}
    openai_compatible = language_models.get("openai_compatible")
    if not isinstance(openai_compatible, dict):
        openai_compatible = {}
    openai_compatible.pop("hipfire", None)
    openai_compatible["minicpm-v"] = zed_entry()
    language_models["openai_compatible"] = openai_compatible
    data["language_models"] = language_models
    return data


def hermes_alias() -> dict:
    return {
        "model": MODEL_ID,
        "provider": "custom",
        "base_url": BASE_URL,
        "api_key": "local",
    }


def merge_hermes(data: dict) -> dict:
    existing = data.get("model_aliases")
    if not isinstance(existing, dict):
        existing = {}
    kept = {}
    for name, entry in existing.items():
        if is_hipfire_id(name):
            continue
        if isinstance(entry, dict) and (
            is_hipfire_id(entry.get("model")) or is_hipfire_url(entry.get("base_url"))
        ):
            continue
        kept[name] = entry
    kept[MODEL_ID] = hermes_alias()
    data["model_aliases"] = kept
    return data


def _toml_header_name(line: str) -> str | None:
    stripped = line.strip()
    if not stripped.startswith("[") or stripped.startswith("[["):
        return None
    if not stripped.endswith("]"):
        return None
    return stripped[1:-1].strip()


def _is_hipfire_grok_header(header: str) -> bool:
    if not header.startswith("model."):
        return False
    rest = header[len("model.") :]
    if rest.startswith('"') and rest.endswith('"'):
        rest = rest[1:-1]
    return is_hipfire_id(rest)


def rewrite_grok_toml(text: str) -> str:
    if not text.endswith("\n") and text:
        text += "\n"
    lines = text.splitlines(keepends=True)
    chunks: list[tuple[str | None, list[str]]] = [(None, [])]
    for line in lines:
        header = _toml_header_name(line)
        if header is not None:
            chunks.append((header, [line]))
        else:
            chunks[-1][1].append(line)
    kept_chunks: list[tuple[str | None, list[str]]] = []
    has_minicpm = False
    for header, body in chunks:
        if header is not None and _is_hipfire_grok_header(header):
            continue
        if header is not None and (
            header in {f'model."{MODEL_ID}"', f"model.{MODEL_ID}"}
        ):
            has_minicpm = True
        kept_chunks.append((header, body))
    out = []
    for header, body in kept_chunks:
        block = "".join(body)
        if header in {"subagents.models", "subagents.roles.local-helper"}:
            # Dead hipfire lanes must not steal the VL GPU; coding stays cloud.
            block = re.sub(
                r'(explore|model)\s*=\s*"(?:' + "|".join(sorted(HIPFIRE_IDS)) + r'|minicpm-v-4\.5)"',
                r'\1 = "grok-4.6"',
                block,
            )
        out.append(block)
    result = "".join(out)
    if not has_minicpm:
        if result and not result.endswith("\n"):
            result += "\n"
        result += (
            f'\n[model."{MODEL_ID}"]\n'
            f'model = "{MODEL_ID}"\n'
            f'base_url = "{BASE_URL}"\n'
            f'name = "{DISPLAY_NAME}"\n'
            "description = "
            '"R9700 visual oracle. Prefer for screenshots and XAML; Pi chat stays longctx."\n'
            'api_backend = "chat_completions"\n'
            'api_key = "local"\n'
            f"context_window = {CTX}\n"
            f"max_completion_tokens = {MAX_TOKENS}\n"
            "supports_backend_search = false\n"
        )
    return result


def strip_jsonc(text: str) -> str:
    lines = []
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("//"):
            continue
        lines.append(line)
    cleaned = "\n".join(lines)
    return re.sub(r",(\s*[}\]])", r"\1", cleaned)


def _load_yaml(path: Path) -> dict | None:
    try:
        import yaml
    except ImportError:
        print(f"minicpm-v-merge-clients: PyYAML missing; skip {path}", file=sys.stderr)
        return None
    if not path.exists():
        return {}
    with path.open(encoding="utf-8") as handle:
        loaded = yaml.safe_load(handle) or {}
    if not isinstance(loaded, dict):
        print(f"minicpm-v-merge-clients: {path} is not a mapping; skipped", file=sys.stderr)
        return None
    return loaded


def _dump_yaml(path: Path, data: dict) -> None:
    import yaml

    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as handle:
        yaml.safe_dump(data, handle, sort_keys=False, allow_unicode=True)
    os.replace(tmp, path)
    path.chmod(0o600)


def _write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")
    os.replace(tmp, path)


def apply_continue() -> None:
    data = _load_yaml(CONTINUE_PATH)
    if data is None:
        return
    merged = merge_continue(data)
    _dump_yaml(CONTINUE_PATH, merged)
    print("minicpm-v-merge-clients: Continue →", MODEL_ID)


def apply_zed() -> None:
    if ZED_PATH.exists():
        raw = ZED_PATH.read_text(encoding="utf-8")
        try:
            data = json.loads(strip_jsonc(raw))
        except json.JSONDecodeError:
            print("minicpm-v-merge-clients: zed settings.json is not JSON; skipped", file=sys.stderr)
            return
        if not isinstance(data, dict):
            return
    else:
        data = {}
    _write_json(ZED_PATH, merge_zed(data))
    print("minicpm-v-merge-clients: Zed →", MODEL_ID)


def apply_hermes() -> None:
    data = _load_yaml(HERMES_PATH)
    if data is None:
        return
    _dump_yaml(HERMES_PATH, merge_hermes(data))
    print("minicpm-v-merge-clients: Hermes →", MODEL_ID)


def apply_grok() -> None:
    if not GROK_PATH.exists():
        return
    original = GROK_PATH.read_text(encoding="utf-8")
    rewritten = rewrite_grok_toml(original)
    if rewritten == original:
        return
    tmp = GROK_PATH.with_suffix(GROK_PATH.suffix + ".tmp")
    tmp.write_text(rewritten, encoding="utf-8")
    os.replace(tmp, GROK_PATH)
    GROK_PATH.chmod(0o600)
    print("minicpm-v-merge-clients: Grok user config →", MODEL_ID)


def main() -> int:
    apply_continue()
    apply_zed()
    apply_hermes()
    apply_grok()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
