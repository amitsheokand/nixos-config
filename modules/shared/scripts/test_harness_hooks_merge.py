#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "harness_hooks_merge",
    Path(__file__).with_name("harness-hooks-merge.py"),
)
mod = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(mod)


class MuseMergeTests(unittest.TestCase):
    def test_rewrites_flat_command_groups(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "settings.json"
            path.write_text(
                json.dumps({
                    "schema_version": 1,
                    "mcpServers": {"headroom": {"command": "headroom"}},
                    "settings": {"toolPrefix": "server", "idleTimeout": 10},
                    "mcp_servers": {
                        "one-grep": {
                            "command": "one-grep",
                            "args": ["serve", "--stdio"],
                        }
                    },
                    "hooks": {
                        "PostToolUse": [{
                            "command": "python3 /tmp/advait-harness-clip",
                            "timeout": 15,
                        }],
                    },
                }),
                encoding="utf-8",
            )
            mod.merge_muse(path)
            data = json.loads(path.read_text(encoding="utf-8"))
            self.assertNotIn("mcpServers", data)
            self.assertNotIn("settings", data)
            group = data["hooks"]["PostToolUse"][0]
            self.assertNotIn("command", group)
            handler = group["hooks"][0]
            self.assertEqual(handler["type"], "command")
            self.assertIn("advait-harness-clip", handler["command"])
            server = data["mcp_servers"]["one-grep"]
            self.assertEqual(server["transport"], "stdio")
            self.assertEqual(server["mode"], "optional")


if __name__ == "__main__":
    unittest.main()
