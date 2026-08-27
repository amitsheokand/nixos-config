#!/usr/bin/env python3
"""Unit tests for hipfire-profile-proxy request rewrite. No GPU."""
from __future__ import annotations

import importlib.util
import json
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "hipfire_profile_proxy",
    Path(__file__).with_name("hipfire-profile-proxy.py"),
)
proxy = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(proxy)

CFG = {
    "backend": "http://127.0.0.1:11435",
    "default_backend": "ornith",
    "backends": {
        "ornith": {
            "tag": "ornith-1.5:35b-a3b",
            "aliases": ["ornith", "ornith-1.5"],
            "speculation": ["off", "mtp"],
            "display_name": "Ornith",
        },
        "qwen38": {
            "tag": "qwen3.8:27b",
            "aliases": ["qwen38", "qwen3.8"],
            "speculation": ["off", "dflash", "mtp"],
            "display_name": "Qwen 3.8",
        },
    },
    "profiles": {
        "forge": {
            "display_name": "Forge",
            "defaults": {
                "reasoning_effort": "medium",
                "chat_template_kwargs": {
                    "enable_thinking": True,
                    "preserve_thinking": True,
                },
            },
            "speculation": "off",
        },
        "feather": {
            "display_name": "Feather",
            "defaults": {"temperature": 0},
            "speculation": "dflash-if-capable",
        },
    },
}


class ApplyRequestTests(unittest.TestCase):
    def test_forge_uses_default_backend_and_lane_defaults(self) -> None:
        body = proxy.apply_request(CFG, {"model": "forge"})
        self.assertEqual(body["model"], "ornith-1.5:35b-a3b")
        self.assertEqual(body["reasoning_effort"], "medium")
        self.assertEqual(body["speculation"], "off")
        self.assertTrue(body["chat_template_kwargs"]["enable_thinking"])

    def test_client_effort_wins(self) -> None:
        body = proxy.apply_request(
            CFG, {"model": "forge", "reasoning_effort": "xhigh"}
        )
        self.assertEqual(body["reasoning_effort"], "xhigh")

    def test_feather_on_ornith_is_mtp_not_dflash(self) -> None:
        body = proxy.apply_request(CFG, {"model": "feather"})
        self.assertEqual(body["model"], "ornith-1.5:35b-a3b")
        self.assertEqual(body["speculation"], "mtp")

    def test_feather_on_qwen_is_dflash(self) -> None:
        cfg = dict(CFG)
        cfg["default_backend"] = "qwen38"
        body = proxy.apply_request(cfg, {"model": "feather"})
        self.assertEqual(body["model"], "qwen3.8:27b")
        self.assertEqual(body["speculation"], "dflash")

    def test_composite_forge_qwen_keeps_lane_defaults(self) -> None:
        body = proxy.apply_request(CFG, {"model": "forge/qwen38"})
        self.assertEqual(body["model"], "qwen3.8:27b")
        self.assertEqual(body["reasoning_effort"], "medium")
        self.assertEqual(body["speculation"], "off")

    def test_qwen38_alias_does_not_inject_lane_defaults(self) -> None:
        body = proxy.apply_request(CFG, {"model": "qwen38"})
        self.assertEqual(body["model"], "qwen3.8:27b")
        self.assertNotIn("reasoning_effort", body)

    def test_unknown_model_is_rejected(self) -> None:
        with self.assertRaises(proxy.UnknownModel):
            proxy.apply_request(CFG, {"model": "not-a-lane"})

    def test_models_list_has_lanes_backends_and_nondefault_composites(self) -> None:
        payload = [item["id"] for item in json.loads(proxy.models_payload(CFG))["data"]]
        self.assertEqual(
            payload,
            [
                "forge",
                "feather",
                "ornith",
                "qwen38",
                "forge/qwen38",
                "feather/qwen38",
            ],
        )


if __name__ == "__main__":
    unittest.main()
