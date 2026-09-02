#!/usr/bin/env python3
"""Unit tests for zvec-grep client MCP merges. No daemon."""
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "zvec_grep_merge_clients",
    Path(__file__).with_name("zvec-grep-merge-clients.py"),
)
merge = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(merge)

URL = "http://127.0.0.1:7999/mcp"


class MergeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def test_grok_appends_section(self) -> None:
        out = merge.merge_grok_text("[ui]\nyolo = false\n", URL)
        self.assertIsNotNone(out)
        assert out is not None
        self.assertIn("[mcp_servers.zvec_grep]", out)
        self.assertIn(f'url = "{URL}"', out)
        self.assertIn("[ui]", out)

    def test_grok_noop_when_current(self) -> None:
        text = merge.grok_block(URL)
        self.assertIsNone(merge.merge_grok_text(text, URL))

    def test_grok_rewrites_url(self) -> None:
        text = '[mcp_servers.zvec_grep]\nurl = "http://127.0.0.1:1/mcp"\nenabled = false\n'
        out = merge.merge_grok_text(text, URL)
        self.assertIsNotNone(out)
        assert out is not None
        self.assertIn(f'url = "{URL}"', out)
        self.assertIn("enabled = true", out)
        self.assertNotIn("enabled = false", out)

    def test_zed_keeps_language_models(self) -> None:
        path = self.root / ".config" / "zed" / "settings.json"
        path.parent.mkdir(parents=True)
        path.write_text(
            json.dumps({"language_models": {"openai_compatible": {"hipfire": {}}}})
            + "\n",
            encoding="utf-8",
        )
        self.assertTrue(merge.merge_zed(self.root))
        data = json.loads(path.read_text(encoding="utf-8"))
        self.assertIn("hipfire", data["language_models"]["openai_compatible"])
        self.assertEqual(data["context_servers"]["zvec_grep"]["url"], URL)
        self.assertFalse(merge.merge_zed(self.root))

    def test_muse_sets_optional_http(self) -> None:
        path = self.root / ".config" / "muse" / "settings.json"
        path.parent.mkdir(parents=True)
        path.write_text(
            json.dumps({"schema_version": 1, "model": "muse-spark-1.2"}) + "\n",
            encoding="utf-8",
        )
        self.assertTrue(merge.merge_muse(self.root))
        data = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(data["schema_version"], 1)
        self.assertEqual(data["model"], "muse-spark-1.2")
        entry = data["mcp_servers"]["zvec_grep"]
        self.assertEqual(entry["transport"], "streamable_http")
        self.assertEqual(entry["mode"], "optional")
        self.assertEqual(entry["url"], URL)

    def test_pi_keeps_other_servers(self) -> None:
        path = self.root / ".pi" / "agent" / "mcp.json"
        path.parent.mkdir(parents=True)
        path.write_text(
            json.dumps(
                {
                    "settings": {"toolPrefix": "server"},
                    "mcpServers": {"other": {"command": "npx"}},
                }
            )
            + "\n",
            encoding="utf-8",
        )
        self.assertTrue(merge.merge_pi(self.root))
        data = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(data["mcpServers"]["other"]["command"], "npx")
        self.assertEqual(data["mcpServers"]["zvec_grep"]["url"], URL)
        self.assertEqual(data["mcpServers"]["zvec_grep"]["lifecycle"], "lazy")

    def test_hermes_keeps_aliases(self) -> None:
        if merge.yaml is None:
            self.skipTest("PyYAML not installed")
        path = self.root / ".hermes" / "config.yaml"
        path.parent.mkdir(parents=True)
        path.write_text("model_aliases:\n  forge:\n    model: forge\n", encoding="utf-8")
        self.assertTrue(merge.merge_hermes(self.root))
        data = merge.yaml.safe_load(path.read_text(encoding="utf-8"))
        self.assertEqual(data["model_aliases"]["forge"]["model"], "forge")
        self.assertEqual(data["mcp_servers"]["zvec_grep"]["url"], URL)
        self.assertFalse(merge.merge_hermes(self.root))


if __name__ == "__main__":
    unittest.main()
