#!/usr/bin/env python3
"""Unit tests for then_run_uptake scan (Cursor replay + gate_*)."""
from __future__ import annotations

import json
import tempfile
import unittest
import unittest.mock
from pathlib import Path

from then_run_uptake import scan


def _write_jsonl(path: Path, rows: list[dict]) -> None:
    path.write_text("".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8")


class UptakeTests(unittest.TestCase):
    def test_gate_then_run(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            session = root / "s.jsonl"
            _write_jsonl(
                session,
                [
                    {
                        "type": "message",
                        "message": {
                            "role": "assistant",
                            "content": [
                                {
                                    "type": "toolCall",
                                    "name": "gate_edit",
                                    "arguments": {
                                        "path": "src/lib.rs",
                                        "then_run": "cargo test -p aikya-com --lib",
                                    },
                                }
                            ],
                        },
                    }
                ],
            )
            counts = scan(root)
            self.assertEqual(counts["gate_edit_or_write"], 1)
            self.assertEqual(counts["then_run"], 1)
            self.assertEqual(counts["native_edit_or_write"], 0)

    def test_cursor_edit_then_shell(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write_jsonl(
                root / "s.jsonl",
                [
                    {
                        "type": "message",
                        "message": {
                            "role": "toolResult",
                            "toolName": "cursor",
                            "details": {"sourceToolName": "edit"},
                            "content": [{"type": "text", "text": "edit src/lib.rs"}],
                        },
                    },
                    {
                        "type": "message",
                        "message": {
                            "role": "toolResult",
                            "toolName": "cursor",
                            "details": {"sourceToolName": "bash"},
                            "content": [{"type": "text", "text": "$ cargo test"}],
                        },
                    },
                ],
            )
            counts = scan(root)
            self.assertEqual(counts["cursor_edit_or_write"], 1)
            self.assertEqual(counts["cursor_adjacent_shell"], 1)
            self.assertEqual(counts["then_run"], 0)

    def test_gate_then_run_not_double_counted(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write_jsonl(
                root / "s.jsonl",
                [
                    {
                        "type": "message",
                        "message": {
                            "role": "assistant",
                            "content": [
                                {
                                    "type": "toolCall",
                                    "name": "gate_edit",
                                    "arguments": {
                                        "path": "src/lib.rs",
                                        "then_run": "cargo test --lib",
                                    },
                                }
                            ],
                        },
                    },
                    {
                        "type": "message",
                        "message": {
                            "role": "toolResult",
                            "toolName": "gate_edit",
                            "content": [
                                {
                                    "type": "text",
                                    "text": "ok\n[then_run:succeeded] cargo test --lib\nok",
                                }
                            ],
                        },
                    },
                ],
            )
            self.assertEqual(scan(root)["then_run"], 1)


if __name__ == "__main__":
    unittest.main()
