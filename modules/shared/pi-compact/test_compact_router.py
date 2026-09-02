#!/usr/bin/env python3
"""Unit tests for pi-compact-router. No GPU, no network servers required."""
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "compact_router",
    Path(__file__).with_name("compact-router.py"),
)
router = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(router)


class PrepareBodyTests(unittest.TestCase):
    def test_injects_focus_and_kills_thinking(self) -> None:
        focus = Path(__file__).with_name("focus.md").read_text()
        body = router.prepare_body(
            {
                "model": "compactor",
                "messages": [{"role": "user", "content": "summarize"}],
                "reasoning_effort": "xhigh",
                "max_think_tokens": 8192,
            },
            focus,
        )
        self.assertEqual(body["messages"][0]["role"], "system")
        self.assertIn("continuation-summary", body["messages"][0]["content"])
        self.assertFalse(body["chat_template_kwargs"]["enable_thinking"])
        self.assertEqual(body["temperature"], 0)
        self.assertNotIn("reasoning_effort", body)
        self.assertNotIn("max_think_tokens", body)

    def test_does_not_duplicate_focus(self) -> None:
        focus = "You are a continuation-summary model."
        first = router.prepare_body({"messages": [{"role": "user", "content": "x"}]}, focus)
        second = router.prepare_body(first, focus)
        systems = [m for m in second["messages"] if m.get("role") == "system"]
        self.assertEqual(len(systems), 1)

    def test_coalesces_extra_system_for_qwen_jinja(self) -> None:
        focus = "You are a continuation-summary model."
        body = router.prepare_body(
            {
                "messages": [
                    {"role": "system", "content": "You are a helpful assistant."},
                    {"role": "user", "content": "summarize"},
                ]
            },
            focus,
        )
        systems = [m for m in body["messages"] if m.get("role") == "system"]
        self.assertEqual(len(systems), 1)
        self.assertEqual(body["messages"][0]["role"], "system")
        self.assertIn("continuation-summary", systems[0]["content"])
        self.assertIn("helpful assistant", systems[0]["content"])


class BlockTests(unittest.TestCase):
    def test_blocks_hipfire_and_desktop_catalog(self) -> None:
        self.assertTrue(router.is_blocked("http://127.0.0.1:11435/v1"))
        self.assertTrue(router.is_blocked("http://127.0.0.1:8080/v1"))
        self.assertTrue(router.is_blocked("http://ai-mac.local:8080/v1"))
        self.assertFalse(router.is_blocked("http://ai-mac.local:8081/v1"))
        self.assertFalse(router.is_blocked("http://127.0.0.1:8092/v1"))

    def test_post_chat_refuses_blocked(self) -> None:
        with self.assertRaises(RuntimeError):
            router.post_chat("http://127.0.0.1:11435/v1", {}, 1.0)


class BackendOrderTests(unittest.TestCase):
    def test_mac_then_local(self) -> None:
        env = {
            "COMPACT_PRIMARY_BASE": "http://ai-mac.local:8081/v1",
            "COMPACT_FALLBACK_BASE": "http://127.0.0.1:8092/v1",
            "COMPACT_PRIMARY_MODEL": "/Users/amitsheokand/models/Compactor-Qwen3.5-4B-4bit",
        }
        with patch.dict("os.environ", env, clear=False):
            rows = router.backends()
        self.assertEqual([row[0] for row in rows], ["primary", "fallback"])
        self.assertEqual(rows[0][2], "/Users/amitsheokand/models/Compactor-Qwen3.5-4B-4bit")


class FitBodyTests(unittest.TestCase):
    def test_clips_huge_user_message(self) -> None:
        huge = "keep-head " + ("x" * 80_000) + " keep-tail-unique"
        body = router.fit_body(
            {"messages": [{"role": "system", "content": "sys"}, {"role": "user", "content": huge}],
             "max_tokens": 8192},
            max_input_tokens=4000,
            max_out=1024,
        )
        self.assertEqual(body["max_tokens"], 1024)
        user = body["messages"][-1]["content"]
        self.assertIn("keep-head", user)
        self.assertIn("keep-tail-unique", user)
        self.assertIn("truncated for compact context", user)
        self.assertLess(router.estimate_tokens(user), 4000)


if __name__ == "__main__":
    unittest.main()
