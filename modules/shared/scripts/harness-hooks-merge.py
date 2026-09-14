#!/usr/bin/env python3
"""Merge Advait harness-clip into Cursor hooks.json and Muse settings.json."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

CLIP = os.environ.get(
    "ADVAIT_HARNESS_CLIP",
    str(Path.home() / ".local" / "bin" / "advait-harness-clip"),
)

CURSOR_ENTRY = {
    "command": f"python3 {CLIP}",
    "timeout": 15,
}
MUSE_ENTRY = {
    "command": f"python3 {CLIP}",
    "timeout": 15,
}


def load(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def has_clip(entries: object) -> bool:
    if not isinstance(entries, list):
        return False
    for entry in entries:
        cmd = entry.get("command") if isinstance(entry, dict) else ""
        if isinstance(cmd, str) and "advait-harness-clip" in cmd:
            return True
    return False


def upsert_list(mapping: dict, key: str, entry: dict) -> None:
    items = mapping.get(key)
    if not isinstance(items, list):
        items = []
        mapping[key] = items
    if not has_clip(items):
        items.append(entry)


def dedupe_commands(entries: list) -> list:
    seen: set[str] = set()
    out = []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        cmd = entry.get("command")
        key = cmd if isinstance(cmd, str) else repr(entry)
        if key in seen:
            continue
        seen.add(key)
        out.append(entry)
    return out


def merge_cursor(path: Path) -> None:
    data = load(path)
    data.setdefault("version", 1)
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        hooks = {}
        data["hooks"] = hooks
    upsert_list(hooks, "preToolUse", {**CURSOR_ENTRY, "matcher": "Shell"})
    upsert_list(hooks, "afterShellExecution", CURSOR_ENTRY)
    upsert_list(hooks, "postToolUse", {**CURSOR_ENTRY, "matcher": "Shell"})
    for key, items in list(hooks.items()):
        if isinstance(items, list):
            hooks[key] = dedupe_commands(items)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def merge_muse(path: Path) -> None:
    data = load(path)
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        hooks = {}
        data["hooks"] = hooks
    # Muse binds one event per hook; keep both PostToolUse and PreCompact.
    upsert_list(hooks, "PostToolUse", MUSE_ENTRY)
    upsert_list(hooks, "PreCompact", MUSE_ENTRY)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    home = Path.home()
    merge_cursor(home / ".cursor" / "hooks.json")
    merge_muse(home / ".config" / "muse" / "settings.json")
    print(f"harness-hooks-merge: clip={CLIP}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
