#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("harness_clip", ROOT / "harness-clip.py")
mod = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(mod)


class HarnessClipTests(unittest.TestCase):
    def test_skips_tiny_output(self) -> None:
        self.assertFalse(mod.should_clip("cargo test --lib", "ok\n"))

    def test_clips_cargo_log(self) -> None:
        body = ("warning: unused\n" + ("x" * 5000) + "\ntest result: ok. 9 passed; 0 failed\n")
        self.assertTrue(mod.should_clip("cargo test -p aikya-com --lib", body))

    def test_green_test_receipt(self) -> None:
        body = "warning: error in name\ntest result: ok. 9 passed; 0 failed\n"
        rec = mod.receipt(Path("/tmp/x.log"), "cargo test --lib", body, [])
        self.assertIn("status=success", rec)

    def test_wraps_cargo_pre_tool(self) -> None:
        wrapped = mod.wrap_diagnostic("cargo test -p aikya-com --lib")
        self.assertIsNotNone(wrapped)
        self.assertIn("tee", wrapped or "")
        self.assertIsNone(mod.wrap_diagnostic("ls src"))

    def test_cursor_command_field(self) -> None:
        self.assertEqual(
            mod.command_of({"command": "cargo test --lib", "output": "hi"}),
            "cargo test --lib",
        )
    unittest.main()
