#!/usr/bin/env python3
"""Unit tests for MiniCPM-V client merge. No GPU."""
from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "minicpm_v_merge_clients",
    Path(__file__).with_name("minicpm-v-merge-clients.py"),
)
merge = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(merge)


class HipfireDetect(unittest.TestCase):
    def test_ids(self) -> None:
        self.assertTrue(merge.is_hipfire_id("forge"))
        self.assertTrue(merge.is_hipfire_id("forge/lfm"))
        self.assertTrue(merge.is_hipfire_id("qwen38"))
        self.assertFalse(merge.is_hipfire_id("minicpm-v-4.5"))
        self.assertFalse(merge.is_hipfire_id("muse-spark-1.2"))
        self.assertFalse(merge.is_hipfire_id("longctx"))

    def test_urls(self) -> None:
        self.assertTrue(merge.is_hipfire_url("http://127.0.0.1:8080/v1"))
        self.assertTrue(merge.is_hipfire_url("http://nixos.local:8080/v1"))
        self.assertTrue(merge.is_hipfire_url("http://192.168.1.15:8080/v1"))
        self.assertTrue(merge.is_hipfire_url("http://127.0.0.1:11435/v1"))
        self.assertFalse(merge.is_hipfire_url("http://127.0.0.1:8093/v1"))
        self.assertFalse(merge.is_hipfire_url("http://127.0.0.1:8091/v1"))
        self.assertFalse(merge.is_hipfire_url("http://127.0.0.1:8082/v1"))
        self.assertFalse(merge.is_hipfire_url("http://ai-mac.local:8080/v1"))


class MergeContinue(unittest.TestCase):
    def test_strips_lanes_keeps_muse(self) -> None:
        data = {
            "models": [
                {
                    "name": "Forge",
                    "provider": "openai",
                    "model": "forge",
                    "apiBase": "http://127.0.0.1:8080/v1",
                    "apiKey": "local",
                },
                {
                    "name": "Muse",
                    "provider": "openai",
                    "model": "muse-spark-1.2",
                    "apiBase": "http://127.0.0.1:8082/v1",
                    "apiKey": "local",
                },
            ],
            "selectedModel": "forge",
        }
        out = merge.merge_continue(data)
        models = out["models"]
        self.assertEqual(models[0]["model"], "minicpm-v-4.5")
        self.assertEqual(models[0]["apiBase"], merge.BASE_URL)
        self.assertEqual(len(models), 2)
        self.assertEqual(models[1]["model"], "muse-spark-1.2")
        self.assertEqual(out["selectedModel"], "minicpm-v-4.5")


class MergeZed(unittest.TestCase):
    def test_replaces_hipfire_keeps_muse(self) -> None:
        data = {
            "agent": {"default_model": {"provider": "openrouter", "model": "z-ai/glm-5"}},
            "language_models": {
                "openai_compatible": {
                    "hipfire": {"api_url": "http://127.0.0.1:8080/v1", "available_models": []},
                    "meta": {"api_url": "http://127.0.0.1:8082/v1"},
                }
            },
        }
        out = merge.merge_zed(data)
        oc = out["language_models"]["openai_compatible"]
        self.assertNotIn("hipfire", oc)
        self.assertEqual(oc["minicpm-v"]["api_url"], merge.BASE_URL)
        self.assertEqual(oc["minicpm-v"]["available_models"][0]["name"], "minicpm-v-4.5")
        self.assertTrue(oc["minicpm-v"]["available_models"][0]["capabilities"]["images"])
        self.assertEqual(oc["meta"]["api_url"], "http://127.0.0.1:8082/v1")
        self.assertEqual(out["agent"]["default_model"]["provider"], "openrouter")


class MergeHermes(unittest.TestCase):
    def test_strips_aliases_keeps_muse(self) -> None:
        data = {
            "model": {"provider": "nous", "default": "openai/gpt-5.6-luna"},
            "model_aliases": {
                "forge": {
                    "model": "forge",
                    "provider": "custom",
                    "base_url": "http://127.0.0.1:8080/v1",
                    "api_key": "local",
                },
                "muse": {
                    "model": "muse-spark-1.2",
                    "provider": "custom",
                    "base_url": "http://127.0.0.1:8082/v1",
                    "api_key": "secret",
                },
            },
        }
        out = merge.merge_hermes(data)
        aliases = out["model_aliases"]
        self.assertNotIn("forge", aliases)
        self.assertEqual(aliases["muse"]["base_url"], "http://127.0.0.1:8082/v1")
        self.assertEqual(aliases["minicpm-v-4.5"]["base_url"], merge.BASE_URL)
        self.assertEqual(out["model"]["default"], "openai/gpt-5.6-luna")


class RewriteGrok(unittest.TestCase):
    def test_drops_qwen38_retargets_subagents(self) -> None:
        text = (
            "[models]\n"
            'default = "grok-4.6"\n'
            "\n"
            "[model.qwen38]\n"
            'model = "qwen38"\n'
            'base_url = "http://192.168.1.15:8080/v1"\n'
            "\n"
            "[subagents.models]\n"
            'explore = "qwen38"\n'
            "\n"
            "[subagents.roles.local-helper]\n"
            'model = "qwen38"\n'
        )
        out = merge.rewrite_grok_toml(text)
        self.assertNotIn("[model.qwen38]", out)
        self.assertIn('[model."minicpm-v-4.5"]', out)
        self.assertIn("127.0.0.1:8093", out)
        self.assertIn('explore = "grok-4.6"', out)
        self.assertIn('model = "grok-4.6"', out)
        self.assertIn('default = "grok-4.6"', out)


class FileRoundtrip(unittest.TestCase):
    def test_zed_and_grok_under_tmp_home(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            zed = home / ".config" / "zed" / "settings.json"
            grok = home / ".grok" / "config.toml"
            zed.parent.mkdir(parents=True)
            grok.parent.mkdir(parents=True)
            zed.write_text(
                '{"language_models":{"openai_compatible":{"hipfire":{"api_url":"http://127.0.0.1:8080/v1"}}}}\n',
                encoding="utf-8",
            )
            grok.write_text('[model.qwen38]\nmodel = "qwen38"\n', encoding="utf-8")
            old_home = merge.HOME
            old_zed = merge.ZED_PATH
            old_grok = merge.GROK_PATH
            merge.HOME = home
            merge.ZED_PATH = zed
            merge.GROK_PATH = grok
            try:
                merge.apply_zed()
                merge.apply_grok()
            finally:
                merge.HOME = old_home
                merge.ZED_PATH = old_zed
                merge.GROK_PATH = old_grok
            zed_data = __import__("json").loads(zed.read_text(encoding="utf-8"))
            self.assertNotIn("hipfire", zed_data["language_models"]["openai_compatible"])
            self.assertIn("minicpm-v", zed_data["language_models"]["openai_compatible"])
            self.assertIn("minicpm-v-4.5", grok.read_text(encoding="utf-8"))
            self.assertNotIn("qwen38", grok.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
