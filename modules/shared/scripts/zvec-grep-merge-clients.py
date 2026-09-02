#!/usr/bin/env python3
"""Register zvec-grep MCP on Pi, Hermes, Grok, Muse, and Zed.

Cursor MCP lives in headroom.nix (single writer of ~/.cursor/mcp.json).
OpenCode is `zg install --target opencode`. This script covers the clients
`zg install` does not know about.

Does not start the daemon. URL defaults to http://127.0.0.1:7999/mcp.
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

MCP_URL = os.environ.get("ZVEC_GREP_MCP_URL", "http://127.0.0.1:7999/mcp")
SERVER = "zvec_grep"
GROK_SECTION = re.compile(r"(?m)^\[mcp_servers\.zvec_grep\][^\[]*")


def home() -> Path:
    return Path(os.environ.get("HOME", "")).expanduser()


def mcp_url() -> str:
    return os.environ.get("ZVEC_GREP_MCP_URL", MCP_URL)


def strip_jsonc(text: str) -> str:
    lines = []
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("//"):
            continue
        lines.append(line)
    return re.sub(r",(\s*[}\]])", r"\1", "\n".join(lines))


def atomic_write(path: Path, text: str, mode: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    if mode is not None:
        tmp.chmod(mode)
    tmp.replace(path)


def load_json(path: Path) -> dict | None:
    if not path.is_file():
        return {}
    try:
        loaded = json.loads(strip_jsonc(path.read_text(encoding="utf-8")))
    except json.JSONDecodeError:
        print(f"zvec-grep-merge: {path} is not JSON; skipped", file=sys.stderr)
        return None
    if not isinstance(loaded, dict):
        print(f"zvec-grep-merge: {path} is not an object; skipped", file=sys.stderr)
        return None
    return loaded


def dump_json(data: dict) -> str:
    return json.dumps(data, indent=2) + "\n"


def hermes_entry(url: str) -> dict:
    return {"url": url}


def muse_entry(url: str) -> dict:
    return {
        "transport": "streamable_http",
        "url": url,
        "enabled": True,
        "mode": "optional",
    }


def zed_entry(url: str) -> dict:
    return {"url": url, "enabled": True}


def pi_server(url: str) -> dict:
    return {"url": url, "lifecycle": "lazy"}


def grok_block(url: str) -> str:
    return f'[mcp_servers.{SERVER}]\nurl = "{url}"\nenabled = true\n'


def merge_grok_text(text: str, url: str) -> str | None:
    desired = grok_block(url)
    match = GROK_SECTION.search(text)
    if match:
        current = match.group(0).strip() + "\n"
        if current == desired:
            return None
        prefix = text[: match.start()].rstrip()
        suffix = text[match.end() :].lstrip("\n")
        out = prefix
        if out:
            out += "\n\n"
        out += desired
        if suffix:
            out = out.rstrip() + "\n\n" + suffix.lstrip()
        if not out.endswith("\n"):
            out += "\n"
        return out
    out = text.rstrip()
    if out:
        out += "\n\n"
    return out + desired


def merge_hermes(root: Path) -> bool:
    if yaml is None:
        print("zvec-grep-merge: PyYAML missing; Hermes skipped", file=sys.stderr)
        return False
    path = root / ".hermes" / "config.yaml"
    data: dict = {}
    if path.is_file():
        loaded = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        if not isinstance(loaded, dict):
            print("zvec-grep-merge: hermes config.yaml is not a mapping; skipped", file=sys.stderr)
            return False
        data = loaded
    servers = data.get("mcp_servers")
    if not isinstance(servers, dict):
        servers = {}
    entry = hermes_entry(mcp_url())
    if servers.get(SERVER) == entry:
        return False
    servers[SERVER] = entry
    data["mcp_servers"] = servers
    tmp = path.with_suffix(".yaml.tmp")
    path.parent.mkdir(parents=True, exist_ok=True)
    with tmp.open("w", encoding="utf-8") as handle:
        yaml.safe_dump(data, handle, sort_keys=False, allow_unicode=True)
    tmp.replace(path)
    path.chmod(stat.S_IRUSR | stat.S_IWUSR)
    print("zvec-grep-merge: Hermes mcp_servers.zvec_grep")
    return True


def merge_zed(root: Path) -> bool:
    path = root / ".config" / "zed" / "settings.json"
    data = load_json(path)
    if data is None:
        return False
    servers = data.get("context_servers")
    if not isinstance(servers, dict):
        servers = {}
    entry = zed_entry(mcp_url())
    if servers.get(SERVER) == entry:
        return False
    servers[SERVER] = entry
    data["context_servers"] = servers
    atomic_write(path, dump_json(data))
    print("zvec-grep-merge: Zed context_servers.zvec_grep")
    return True


def merge_muse(root: Path) -> bool:
    path = root / ".config" / "muse" / "settings.json"
    data = load_json(path)
    if data is None:
        return False
    if data.get("schema_version") not in (None, 1):
        print("zvec-grep-merge: muse settings schema_version is not 1; skipped", file=sys.stderr)
        return False
    data["schema_version"] = 1
    servers = data.get("mcp_servers")
    if not isinstance(servers, dict):
        servers = {}
    entry = muse_entry(mcp_url())
    if servers.get(SERVER) == entry:
        return False
    servers[SERVER] = entry
    data["mcp_servers"] = servers
    atomic_write(path, dump_json(data))
    print("zvec-grep-merge: Muse mcp_servers.zvec_grep")
    return True


def merge_grok(root: Path) -> bool:
    path = root / ".grok" / "config.toml"
    text = path.read_text(encoding="utf-8") if path.is_file() else ""
    updated = merge_grok_text(text, mcp_url())
    if updated is None:
        return False
    atomic_write(path, updated)
    print("zvec-grep-merge: Grok mcp_servers.zvec_grep")
    return True


def merge_pi(root: Path) -> bool:
    path = root / ".pi" / "agent" / "mcp.json"
    data = load_json(path)
    if data is None:
        return False
    settings = data.get("settings")
    if not isinstance(settings, dict):
        settings = {}
    settings.setdefault("toolPrefix", "server")
    settings.setdefault("idleTimeout", 10)
    servers = data.get("mcpServers")
    if not isinstance(servers, dict):
        servers = {}
    entry = pi_server(mcp_url())
    if servers.get(SERVER) == entry and data.get("settings") == settings:
        return False
    servers[SERVER] = entry
    data["settings"] = settings
    data["mcpServers"] = servers
    atomic_write(path, dump_json(data), mode=stat.S_IRUSR | stat.S_IWUSR)
    print("zvec-grep-merge: Pi mcpServers.zvec_grep")
    return True


def main() -> int:
    root = home()
    if not str(root):
        print("zvec-grep-merge: HOME is unset", file=sys.stderr)
        return 1
    merge_hermes(root)
    merge_zed(root)
    merge_muse(root)
    merge_grok(root)
    merge_pi(root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
