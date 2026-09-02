#!/usr/bin/env python3
"""Unit tests for muse-spark-proxy tool_call_id rewrite. No network."""
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "muse_spark_proxy",
    Path(__file__).with_name("muse-spark-proxy.py"),
)
proxy = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(proxy)

MODEL = "muse-spark-1.2"


def tool_call(call_id: str, name: str = "read_file") -> dict:
    return {
        "id": call_id,
        "type": "function",
        "function": {"name": name, "arguments": "{}"},
    }


class UniquifyTests(unittest.TestCase):
    def test_second_round_call_0_becomes_call_1(self) -> None:
        messages = [
            {"role": "user", "content": "hi"},
            {"role": "assistant", "tool_calls": [tool_call("call_0")]},
            {"role": "tool", "tool_call_id": "call_0", "content": "a"},
            {"role": "assistant", "tool_calls": [tool_call("call_0")]},
            {"role": "tool", "tool_call_id": "call_0", "content": "b"},
        ]
        out = proxy.uniquify_tool_call_ids(messages)
        self.assertEqual(out[1]["tool_calls"][0]["id"], "call_0")
        self.assertEqual(out[2]["tool_call_id"], "call_0")
        self.assertEqual(out[3]["tool_calls"][0]["id"], "call_1")
        self.assertEqual(out[4]["tool_call_id"], "call_1")
        ids = [out[1]["tool_calls"][0]["id"], out[3]["tool_calls"][0]["id"]]
        self.assertEqual(len(set(ids)), 2)

    def test_parallel_tools_same_turn(self) -> None:
        messages = [
            {
                "role": "assistant",
                "tool_calls": [tool_call("call_0"), tool_call("call_1", "grep")],
            },
            {"role": "tool", "tool_call_id": "call_0", "content": "a"},
            {"role": "tool", "tool_call_id": "call_1", "content": "b"},
        ]
        out = proxy.uniquify_tool_call_ids(messages)
        self.assertEqual(out[0]["tool_calls"][0]["id"], "call_0")
        self.assertEqual(out[0]["tool_calls"][1]["id"], "call_1")
        self.assertEqual(out[1]["tool_call_id"], "call_0")
        self.assertEqual(out[2]["tool_call_id"], "call_1")

    def test_duplicate_ids_in_one_assistant_turn(self) -> None:
        messages = [
            {
                "role": "assistant",
                "tool_calls": [tool_call("call_0"), tool_call("call_0", "grep")],
            },
            {"role": "tool", "tool_call_id": "call_0", "content": "a"},
            {"role": "tool", "tool_call_id": "call_0", "content": "b"},
        ]
        out = proxy.uniquify_tool_call_ids(messages)
        self.assertEqual(out[0]["tool_calls"][0]["id"], "call_0")
        self.assertEqual(out[0]["tool_calls"][1]["id"], "call_1")
        self.assertEqual(out[1]["tool_call_id"], "call_0")
        self.assertEqual(out[2]["tool_call_id"], "call_1")

    def test_apply_chat_request_leaves_non_messages(self) -> None:
        body = proxy.apply_chat_request({"model": MODEL, "stream": True})
        self.assertEqual(body["model"], MODEL)
        self.assertTrue(body["stream"])

    def test_original_messages_not_mutated(self) -> None:
        messages = [
            {"role": "assistant", "tool_calls": [tool_call("call_0")]},
            {"role": "tool", "tool_call_id": "call_0", "content": "a"},
            {"role": "assistant", "tool_calls": [tool_call("call_0")]},
            {"role": "tool", "tool_call_id": "call_0", "content": "b"},
        ]
        proxy.uniquify_tool_call_ids(messages)
        self.assertEqual(messages[2]["tool_calls"][0]["id"], "call_0")
        self.assertEqual(messages[3]["tool_call_id"], "call_0")


class MetaEnvParseTests(unittest.TestCase):
    def test_plain_assignment(self) -> None:
        self.assertEqual(
            proxy.parse_meta_env_line("MODEL_API_KEY=sk-test"),
            ("MODEL_API_KEY", "sk-test"),
        )

    def test_export_and_quotes(self) -> None:
        self.assertEqual(
            proxy.parse_meta_env_line('export MODEL_API_KEY="sk-test"'),
            ("MODEL_API_KEY", "sk-test"),
        )
        self.assertEqual(
            proxy.parse_meta_env_line("export META_API_KEY='sk-test'"),
            ("META_API_KEY", "sk-test"),
        )

    def test_empty_value_is_ignored(self) -> None:
        self.assertIsNone(proxy.parse_meta_env_line('export MODEL_API_KEY=""'))
        self.assertIsNone(proxy.parse_meta_env_line("MODEL_API_KEY="))

    def test_comments(self) -> None:
        self.assertIsNone(proxy.parse_meta_env_line("# MODEL_API_KEY=sk-test"))


if __name__ == "__main__":
    unittest.main()
