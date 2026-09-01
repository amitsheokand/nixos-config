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
            "context_window": 49152,
            "max_tokens": 16384,
            "max_seq": 65536,
        },
        "qwen38": {
            "tag": "qwen3.8:27b",
            "aliases": ["qwen38", "qwen3.8"],
            "speculation": ["off", "dflash", "mtp"],
            "display_name": "Qwen 3.8",
            "context_window": 32768,
            "max_tokens": 8192,
            "max_seq": 65536,
        },
    },
    "profiles": {
        "forge": {
            "display_name": "Forge",
            "context_window": 49152,
            "max_tokens": 16384,
            "max_think_tokens": 2048,
            "defaults": {
                "reasoning_effort": "medium",
                "max_think_tokens": 2048,
                "chat_template_kwargs": {
                    "enable_thinking": True,
                    "preserve_thinking": False,
                },
            },
            "speculation": "off",
        },
        "feather": {
            "display_name": "Feather",
            "backend": "qwen38",
            "context_window": 32768,
            "max_tokens": 8192,
            "max_think_tokens": 512,
            "defaults": {
                "temperature": 0,
                "reasoning_effort": "low",
                "max_think_tokens": 512,
                "max_tokens": 8192,
                "chat_template_kwargs": {
                    "enable_thinking": True,
                    "preserve_thinking": False,
                },
            },
            "speculation": "dflash-if-capable",
        },
    },
}


class ApplyRequestTests(unittest.TestCase):
    def test_forge_uses_default_backend_and_lane_defaults(self) -> None:
        body = proxy.apply_request(CFG, {"model": "forge"})
        self.assertEqual(body["model"], "ornith-1.5:35b-a3b")
        self.assertEqual(body["reasoning_effort"], "medium")
        self.assertNotIn("speculation", body)
        self.assertEqual(body["max_tokens"], 16384)
        self.assertEqual(body["max_think_tokens"], 2048)
        self.assertTrue(body["chat_template_kwargs"]["enable_thinking"])
        self.assertFalse(body["chat_template_kwargs"]["preserve_thinking"])

    def test_client_effort_wins(self) -> None:
        body = proxy.apply_request(
            CFG, {"model": "forge", "reasoning_effort": "xhigh"}
        )
        self.assertEqual(body["reasoning_effort"], "xhigh")

    def test_feather_pins_qwen38_dflash(self) -> None:
        body = proxy.apply_request(CFG, {"model": "feather"})
        self.assertEqual(body["model"], "qwen3.8:27b")
        self.assertEqual(body["speculation"], "dflash")
        self.assertEqual(body["reasoning_effort"], "low")
        self.assertEqual(body["max_think_tokens"], 512)
        self.assertEqual(body["max_tokens"], 8192)
        self.assertTrue(body["chat_template_kwargs"]["enable_thinking"])
        self.assertFalse(body["chat_template_kwargs"]["preserve_thinking"])

    def test_feather_ornith_composite_is_mtp(self) -> None:
        body = proxy.apply_request(CFG, {"model": "feather/ornith"})
        self.assertEqual(body["model"], "ornith-1.5:35b-a3b")
        self.assertEqual(body["speculation"], "mtp")
        self.assertEqual(body["reasoning_effort"], "low")

    def test_client_think_cap_wins(self) -> None:
        body = proxy.apply_request(
            CFG, {"model": "feather", "max_think_tokens": 256}
        )
        self.assertEqual(body["max_think_tokens"], 256)

    def test_feather_on_qwen_is_dflash(self) -> None:
        cfg = dict(CFG)
        cfg["default_backend"] = "qwen38"
        body = proxy.apply_request(cfg, {"model": "feather"})
        self.assertEqual(body["model"], "qwen3.8:27b")
        self.assertEqual(body["speculation"], "dflash")

    def test_composite_forge_qwen_keeps_lane_defaults(self) -> None:
        body = proxy.apply_request(CFG, {"model": "forge/qwen38"})
        self.assertEqual(body["model"], "qwen3.8:27b")
        self.assertNotIn("speculation", body)

    def test_qwen38_alias_does_not_inject_lane_defaults(self) -> None:
        body = proxy.apply_request(CFG, {"model": "qwen38"})
        self.assertEqual(body["model"], "qwen3.8:27b")
        self.assertNotIn("reasoning_effort", body)
        self.assertEqual(body["max_tokens"], 8192)

    def test_client_max_tokens_is_clamped(self) -> None:
        body = proxy.apply_request(CFG, {"model": "forge", "max_tokens": 999999})
        self.assertEqual(body["max_tokens"], 16384)

    def test_oversize_prompt_is_rejected(self) -> None:
        body = {
            "model": "forge",
            "max_tokens": 16384,
            "messages": [{"role": "user", "content": "x" * 200_000}],
        }
        with self.assertRaises(proxy.RequestTooLarge):
            proxy.apply_request(CFG, body)

    def test_mid_window_prompt_clamps_max_tokens_instead_of_413(self) -> None:
        # ~60k chars/2 would 413 against forge's 49k window once 16k gen is
        # reserved. GPU max_seq is 65k; clamp generation, do not refuse.
        body = proxy.apply_request(
            CFG,
            {
                "model": "forge",
                "max_tokens": 16384,
                "messages": [{"role": "user", "content": "x" * 120_000}],
            },
        )
        self.assertEqual(body["model"], "ornith-1.5:35b-a3b")
        self.assertLessEqual(body["max_tokens"], 16384)
        self.assertGreater(body["max_tokens"], 0)
        self.assertEqual(body["max_tokens"], 65536 - 60_000 - 1)

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
                "feather/ornith",
            ],
        )

    def test_small_max_tokens_is_floored_for_thinking(self) -> None:
        body = proxy.apply_request(CFG, {"model": "forge", "max_tokens": 32})
        self.assertEqual(body["max_think_tokens"], 2048)
        self.assertEqual(body["max_tokens"], 2048 + proxy.THINK_ANSWER_ROOM)

    def test_unavailable_backend_is_omitted_from_catalog(self) -> None:
        cfg = json.loads(json.dumps(CFG))
        cfg["backends"]["ornith"]["available"] = False
        cfg["default_backend"] = "qwen38"
        payload = [item["id"] for item in json.loads(proxy.models_payload(cfg))["data"]]
        self.assertEqual(payload, ["forge", "feather", "qwen38"])
        body = proxy.apply_request(cfg, {"model": "feather/ornith"})
        self.assertEqual(body["model"], "ornith-1.5:35b-a3b")

    def test_forge_pin_qwen38_rewrites_tag(self) -> None:
        cfg = dict(CFG)
        profiles = dict(cfg["profiles"])
        forge = dict(profiles["forge"])
        forge["backend"] = "qwen38"
        profiles["forge"] = forge
        cfg["profiles"] = profiles
        body = proxy.apply_request(cfg, {"model": "forge"})
        self.assertEqual(body["model"], "qwen3.8:27b")
        self.assertNotIn("speculation", body)


if __name__ == "__main__":
    unittest.main()
