#!/usr/bin/env python3
"""Register one-grep on Grok + Zed, and drop leftover zvec_grep MCP entries.

Cursor / OpenCode / Pi / Muse / Hermes / Command Code are handled by
programs.one-grep. This covers the two harnesses that module does not, and
strips HTTP zvec_grep so agents do not keep calling :7999.
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

ZVEC_KEYS = ("zvec_grep", "zvec-grep")
GROK_ZVEC = re.compile(r"(?m)^\[mcp_servers\.(?:zvec_grep|zvec-grep)\][^\[]*")


def home() -> Path:
    return Path(os.environ.get("HOME", "")).expanduser()


def command() -> str:
    return os.environ.get(
        "ONE_GREP",
        str(home() / ".local" / "bin" / "one-grep"),
    )


def stdio_entry(exe: str) -> dict:
    return {"command": exe, "args": ["serve", "--stdio"]}


def grok_block(exe: str) -> str:
    return (
        "[mcp_servers.one-grep]\n"
        f'command = "{exe}"\n'
        'args = ["serve", "--stdio"]\n'
        "enabled = true\n"
    )


def strip_jsonc(text: str) -> str:
    lines = []
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("//"):
            continue
        lines.append(line)
    return re.sub(r",(\s*[}\]])", r"\1", "\n".join(lines))


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)


def load_json(path: Path) -> dict | None:
    if not path.is_file():
        return {}
    try:
        loaded = json.loads(strip_jsonc(path.read_text(encoding="utf-8")))
    except json.JSONDecodeError:
        print(f"one-grep-extra: {path} is not JSON; skipped", file=sys.stderr)
        return None
    if not isinstance(loaded, dict):
        print(f"one-grep-extra: {path} is not an object; skipped", file=sys.stderr)
        return None
    return loaded


def drop_zvec(mapping: dict) -> bool:
    changed = False
    for key in ZVEC_KEYS:
        if key in mapping:
            del mapping[key]
            changed = True
    return changed


def upsert_json_map(path: Path, map_key: str, name: str, entry: dict) -> None:
    data = load_json(path)
    if data is None:
        return
    servers = data.get(map_key)
    if not isinstance(servers, dict):
        servers = {}
    changed = drop_zvec(servers)
    if servers.get(name) != entry:
        servers[name] = entry
        changed = True
    if not changed:
        return
    data[map_key] = servers
    atomic_write(path, json.dumps(data, indent=2) + "\n")
    print(f"one-grep-extra: {path} {map_key}.{name}")


def strip_json_map(path: Path, map_key: str) -> None:
    data = load_json(path)
    if data is None or not path.is_file():
        return
    servers = data.get(map_key)
    if not isinstance(servers, dict) or not drop_zvec(servers):
        return
    data[map_key] = servers
    atomic_write(path, json.dumps(data, indent=2) + "\n")
    print(f"one-grep-extra: stripped zvec from {path} {map_key}")


def merge_grok(root: Path, exe: str | None) -> None:
    path = root / ".grok" / "config.toml"
    text = path.read_text(encoding="utf-8") if path.is_file() else ""
    stripped = GROK_ZVEC.sub("", text)
    stripped = re.sub(r"\n{3,}", "\n\n", stripped).strip()
    if exe:
        desired = grok_block(exe)
        match = re.search(r"(?m)^\[mcp_servers\.one-grep\][^\[]*", stripped)
        if match:
            current = match.group(0).strip() + "\n"
            if current == desired and stripped == text.strip():
                return
            prefix = stripped[: match.start()].rstrip()
            suffix = stripped[match.end() :].lstrip("\n")
            out = prefix
            if out:
                out += "\n\n"
            out += desired
            if suffix:
                out = out.rstrip() + "\n\n" + suffix.lstrip()
        else:
            out = stripped
            if out:
                out += "\n\n"
            out += desired
        if not out.endswith("\n"):
            out += "\n"
        atomic_write(path, out)
        print("one-grep-extra: Grok mcp_servers.one-grep")
        return
    if stripped != text.strip():
        atomic_write(path, stripped + ("\n" if stripped else ""))
        print("one-grep-extra: stripped Grok mcp_servers.zvec_grep")


def strip_hermes(root: Path) -> None:
    path = root / ".hermes" / "config.yaml"
    if not path.is_file():
        return
    lines = path.read_text(encoding="utf-8").splitlines()
    out: list[str] = []
    skip = False
    changed = False
    for line in lines:
        if skip:
            if line.startswith("    ") or line.startswith("\t"):
                continue
            if line.startswith("  ") and line.strip() and not line.startswith("  -"):
                skip = False
            elif not line.strip():
                skip = False
            else:
                continue
        if line.startswith("  zvec_grep:") or line.startswith("  zvec-grep:"):
            skip = True
            changed = True
            continue
        out.append(line)
    if not changed:
        return
    text = "\n".join(out)
    if not text.endswith("\n"):
        text += "\n"
    atomic_write(path, text)
    print("one-grep-extra: stripped Hermes mcp_servers.zvec_grep")


def main() -> int:
    root = home()
    if not str(root):
        print("one-grep-extra: HOME is unset", file=sys.stderr)
        return 1
    exe = command()
    have = os.path.isfile(exe) and os.access(exe, os.X_OK)
    if not have:
        print("one-grep-extra: binary missing; leaving zvec_grep MCP in place", file=sys.stderr)
        return 0

    strip_json_map(root / ".cursor" / "mcp.json", "mcpServers")
    strip_json_map(root / ".config" / "opencode" / "opencode.json", "mcp")
    strip_json_map(root / ".pi" / "agent" / "mcp.json", "mcpServers")
    strip_json_map(root / ".commandcode" / "mcp.json", "mcpServers")
    muse = root / ".config" / "muse" / "settings.json"
    strip_json_map(muse, "mcpServers")
    strip_json_map(muse, "mcp_servers")
    strip_hermes(root)

    merge_grok(root, exe)
    upsert_json_map(root / ".config" / "zed" / "settings.json", "context_servers", "one-grep", {
        **stdio_entry(exe),
        "enabled": True,
    })
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
