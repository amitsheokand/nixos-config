#!/usr/bin/env python3
"""Count Action Fusion uptake in Pi session JSONL (no prompt search)."""
from __future__ import annotations

import json
import sys
from pathlib import Path

SESSIONS = Path.home() / ".pi" / "agent" / "sessions"


def scan(root: Path) -> tuple[int, int, int]:
    edits = 0
    fused = 0
    bash_after_edit = 0
    for path in root.rglob("*.jsonl"):
        pending_edit = False
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
                for block in msg.get("content") or []:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") not in {"toolCall", "toolUse"}:
                        continue
                    name = block.get("name") or block.get("toolName")
                    args = block.get("arguments") or block.get("input") or {}
                    if name in {"edit", "write"}:
                        edits += 1
                        pending_edit = True
                        if isinstance(args, dict) and str(args.get("then_run") or "").strip():
                            fused += 1
                            pending_edit = False
                    elif name == "bash" and pending_edit:
                        bash_after_edit += 1
                        pending_edit = False
            elif role == "toolResult":
                text = ""
                for part in msg.get("content") or []:
                    if isinstance(part, dict) and isinstance(part.get("text"), str):
                        text += part["text"]
                if "[then_run:" in text:
                    fused += 1
                    pending_edit = False
    return edits, fused, bash_after_edit


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else SESSIONS
    if not root.is_dir():
        print(f"no sessions at {root}", file=sys.stderr)
        return 1
    edits, fused, adjacent = scan(root)
    rate = (100.0 * fused / edits) if edits else 0.0
    print(f"edit_or_write={edits}")
    print(f"then_run={fused}")
    print(f"adjacent_bash={adjacent}")
    print(f"uptake_pct={rate:.1f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
