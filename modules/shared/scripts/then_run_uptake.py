#!/usr/bin/env python3
"""Count Action Fusion uptake in Pi session JSONL (no prompt search).

Counts Pi native edit/write, non-overlapping gate_edit/gate_write (Cursor
bridge), then_run, adjacent Pi bash, and Cursor host Edit followed by Shell.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

SESSIONS = Path.home() / ".pi" / "agent" / "sessions"
GATE_TOOLS = {"gate_edit", "gate_write"}
MUTATION_TOOLS = {"edit", "write", *GATE_TOOLS}
CURSOR_EDIT = {"edit", "write", "StrReplace", "strreplace"}
CURSOR_SHELL = {"bash", "shell", "shelltool"}


def _source_tool(msg: dict) -> str:
    details = msg.get("details")
    if isinstance(details, dict):
        source = details.get("sourceToolName")
        if isinstance(source, str) and source.strip():
            return source.strip()
    return str(msg.get("toolName") or "")


def scan(root: Path) -> dict[str, int]:
    native = 0
    gate = 0
    cursor_edit = 0
    fused = 0
    adjacent_bash = 0
    cursor_adjacent_shell = 0
    for path in root.rglob("*.jsonl"):
        pending_native = False
        pending_cursor = False
        counted_then_run = False
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(row, dict):
                continue
            msg = row.get("message") if isinstance(row.get("message"), dict) else row
            role = msg.get("role")
            if role == "assistant":
                counted_then_run = False
                for block in msg.get("content") or []:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") not in {"toolCall", "toolUse"}:
                        continue
                    name = block.get("name") or block.get("toolName")
                    args = block.get("arguments") or block.get("input") or {}
                    if name in MUTATION_TOOLS:
                        if name in GATE_TOOLS:
                            gate += 1
                        else:
                            native += 1
                        pending_native = True
                        pending_cursor = False
                        if isinstance(args, dict) and str(args.get("then_run") or "").strip():
                            fused += 1
                            pending_native = False
                            counted_then_run = True
                    elif name == "bash" and pending_native:
                        adjacent_bash += 1
                        pending_native = False
            elif role == "toolResult":
                text = ""
                for part in msg.get("content") or []:
                    if isinstance(part, dict) and isinstance(part.get("text"), str):
                        text += part["text"]
                if "[then_run:" in text:
                    if not counted_then_run:
                        fused += 1
                    pending_native = False
                    pending_cursor = False
                    counted_then_run = False
                    continue
                source = _source_tool(msg).lower()
                if msg.get("toolName") == "cursor" or source in CURSOR_EDIT | CURSOR_SHELL:
                    if source in CURSOR_EDIT:
                        cursor_edit += 1
                        pending_cursor = True
                        pending_native = False
                    elif source in CURSOR_SHELL and pending_cursor:
                        cursor_adjacent_shell += 1
                        pending_cursor = False
    return {
        "native_edit_or_write": native,
        "gate_edit_or_write": gate,
        "cursor_edit_or_write": cursor_edit,
        "then_run": fused,
        "adjacent_bash": adjacent_bash,
        "cursor_adjacent_shell": cursor_adjacent_shell,
    }


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else SESSIONS
    if not root.is_dir():
        print(f"no sessions at {root}", file=sys.stderr)
        return 1
    counts = scan(root)
    edits = (
        counts["native_edit_or_write"]
        + counts["gate_edit_or_write"]
        + counts["cursor_edit_or_write"]
    )
    rate = (100.0 * counts["then_run"] / edits) if edits else 0.0
    for key, value in counts.items():
        print(f"{key}={value}")
    print(f"edit_or_write={edits}")
    print(f"uptake_pct={rate:.1f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
