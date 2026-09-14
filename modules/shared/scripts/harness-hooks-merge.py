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
MUSE_HANDLER = {
    "type": "command",
    "command": f"python3 {CLIP}",
    "timeout": 15,
}
MUSE_GROUP = {"hooks": [MUSE_HANDLER]}


def load(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def clip_in_command(cmd: object) -> bool:
    return isinstance(cmd, str) and "advait-harness-clip" in cmd


def has_clip(entries: object) -> bool:
    if not isinstance(entries, list):
        return False
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        if clip_in_command(entry.get("command")):
            return True
        inner = entry.get("hooks")
        if isinstance(inner, list):
            for handler in inner:
                if isinstance(handler, dict) and clip_in_command(handler.get("command")):
                    return True
    return False


def upsert_list(mapping: dict, key: str, entry: dict) -> None:
    items = mapping.get(key)
    if not isinstance(items, list):
        items = []
        mapping[key] = items
    if not has_clip(items):
        items.append(entry)


def command_key(entry: dict) -> str:
    cmd = entry.get("command")
    if isinstance(cmd, str):
        return cmd
    inner = entry.get("hooks")
    if isinstance(inner, list):
        for handler in inner:
            if isinstance(handler, dict) and isinstance(handler.get("command"), str):
                return str(handler["command"])
    return repr(entry)


def dedupe_commands(entries: list) -> list:
    seen: set[str] = set()
    out = []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        key = command_key(entry)
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


def normalize_muse_groups(items: object) -> list:
    out: list = []
    if not isinstance(items, list):
        return out
    for entry in items:
        if not isinstance(entry, dict):
            continue
        if isinstance(entry.get("hooks"), list):
            out.append(entry)
            continue
        if clip_in_command(entry.get("command")):
            continue
        cmd = entry.get("command")
        if isinstance(cmd, str) and cmd:
            handler = {"type": "command", "command": cmd}
            if isinstance(entry.get("timeout"), int):
                handler["timeout"] = entry["timeout"]
            out.append({"hooks": [handler]})
    return out


def merge_muse(path: Path) -> None:
    data = load(path)
    data.pop("mcpServers", None)
    settings = data.get("settings")
    if isinstance(settings, dict) and "toolPrefix" in settings:
        data.pop("settings", None)
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        hooks = {}
        data["hooks"] = hooks
    for event in ("PostToolUse", "PreCompact"):
        hooks[event] = normalize_muse_groups(hooks.get(event))
        upsert_list(hooks, event, dict(MUSE_GROUP))
        hooks[event] = dedupe_commands(hooks[event])
    servers = data.get("mcp_servers")
    if not isinstance(servers, dict):
        servers = {}
        data["mcp_servers"] = servers
    for name, server in list(servers.items()):
        if not isinstance(server, dict):
            continue
        if "url" in server:
            server.setdefault("transport", "streamable_http")
        else:
            server.setdefault("transport", "stdio")
        server.setdefault("enabled", True)
        server.setdefault("mode", "optional")
        servers[name] = server
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
