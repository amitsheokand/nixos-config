#!/usr/bin/env python3
"""Unit tests for overflow-pick. No network."""
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "overflow_pick",
    Path(__file__).with_name("overflow-pick.py"),
)
pick = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(pick)


def aa(**kwargs):
    row = {
        "slug": "nemotron-3-5-lightning",
        "name": "Nemotron 3.5 Lightning",
        "ii": 13.64,
        "pin": 0.06,
        "pout": 0.2,
        "ctx": 1_000_000,
        "reasoning": True,
    }
    row.update(kwargs)
    return row


def live(**kwargs):
    row = {
        "catalog": "openrouter",
        "id": "nvidia/nemotron-3.5-lightning:free",
        "name": "Lightning free",
        "ctx": 1_000_000,
        "max_tokens": 131072,
        "pin": 0.0,
        "pout": 0.0,
        "free": True,
        "reasoning": True,
        "inputs": ["text"],
    }
    row.update(kwargs)
    return row


class OverflowPickTests(unittest.TestCase):
    def test_bans_share_by_default(self) -> None:
        self.assertTrue(pick.is_banned("poolside/laguna-s-2.1:free"))
        self.assertTrue(pick.is_banned("liquid/lfm-2.5-2.6b:free"))
        self.assertTrue(pick.is_banned("muse-spark-1.3-contributor-free"))
        self.assertTrue(pick.is_banned("openai/gpt-5.6-luna-pro:batch"))
        self.assertTrue(pick.is_banned("~deepseek/deepseek-v4-flash-latest"))
        self.assertFalse(pick.is_banned("nvidia/nemotron-3.5-lightning:free"))

    def test_match_or_and_zen_ids(self) -> None:
        catalog = {
            "nemotron-3-5-lightning": aa(),
            "nvidia-nemotron-3-ultra-550b-a55b": aa(
                slug="nvidia-nemotron-3-ultra-550b-a55b",
                name="Ultra",
                ii=23.41,
            ),
            "north-mini-code": aa(slug="north-mini-code", name="North Mini", ii=12.84),
            "gpt-oss-120b": aa(slug="gpt-oss-120b", name="gpt-oss-120b", ii=12.35),
        }
        self.assertEqual(
            pick.match_aa("nvidia/nemotron-3.5-lightning:free", catalog)["slug"],
            "nemotron-3-5-lightning",
        )
        self.assertEqual(
            pick.match_aa("nemotron-3-ultra-free", catalog)["slug"],
            "nvidia-nemotron-3-ultra-550b-a55b",
        )
        self.assertEqual(
            pick.match_aa("cohere/north-mini-code:free", catalog)["slug"],
            "north-mini-code",
        )
        self.assertEqual(
            pick.match_aa("openai/gpt-oss-120b", catalog)["slug"],
            "gpt-oss-120b",
        )

    def test_parse_aa_skips_creator_slugs(self) -> None:
        blob = (
            '{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","slug":"cohere","name":"Cohere"}'
            '{"slug":"nemotron-3-5-lightning","name":"Lightning",'
            '"intelligenceIndex":13.6,"contextWindowTokens":1000000,'
            '"price1mInputTokens":0.06,"price1mOutputTokens":0.2,"isReasoning":true}'
        )
        models = pick.parse_aa_blob(blob)
        self.assertNotIn("cohere", models)
        self.assertEqual(models["nemotron-3-5-lightning"]["ii"], 13.6)

    def test_picks_best_live_not_a_fixed_id(self) -> None:
        catalog = {
            "inkling": aa(slug="inkling", name="Inkling", ii=25.54),
            "nemotron-3-5-lightning": aa(),
            "gpt-oss-120b": aa(slug="gpt-oss-120b", name="gpt-oss-120b", ii=12.35),
            "glm-5-3-flash": aa(slug="glm-5-3-flash", name="GLM-5.3 Flash", ii=41.91),
        }
        rows = [
            live(),
            live(
                id="thinkingmachines/inkling:free",
                name="Inkling free",
            ),
            live(
                id="openai/gpt-oss-120b",
                name="gpt-oss-120b",
                pin=0.037,
                pout=0.17,
                free=False,
            ),
            live(
                id="z-ai/glm-5.3-flash",
                name="GLM flash",
                pin=0.11,
                pout=0.34,
                free=False,
            ),
            live(
                catalog="zen",
                id="nemotron-3.5-lightning-free",
                name="Zen lightning",
            ),
        ]
        payload = pick.build_assignment(
            catalog, rows, "https://artificialanalysis.ai/leaderboards/models",
            now=datetime(2026, 9, 9, 21, 0, tzinfo=timezone.utc),
        )
        self.assertEqual(payload["date"], "2026-09-09")
        self.assertEqual(payload["free"]["openrouter"], "thinkingmachines/inkling:free")
        self.assertFalse(payload["free"]["confidential_ok"])
        self.assertEqual(payload["cheap"]["openrouter"], "z-ai/glm-5.3-flash")
        self.assertTrue(payload["cheap"]["confidential_ok"])
        self.assertNotEqual(payload["free"]["model"], "stealth/ox-alpha")

    def test_assign_reuses_today(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        home = Path(tmp.name)
        dest = home / ".pi" / "agent"
        dest.mkdir(parents=True)
        (dest / "overflow.json").write_text(
            json.dumps({
                "date": pick.today_str(),
                "free": {"pi": "openrouter/already-assigned"},
                "cheap": {"pi": "openrouter/cheap-assigned"},
            }),
            encoding="utf-8",
        )
        loaded = pick.load_today(dest)
        self.assertEqual(loaded["free"]["pi"], "openrouter/already-assigned")

    def test_extension_registers_openrouter_ids(self) -> None:
        ts = pick.render_extension([
            {
                "openrouter": "thinkingmachines/inkling:free",
                "name": "Inkling",
                "usd_per_m_in": 0,
                "usd_per_m_out": 0,
                "confidential_ok": False,
                "reasoning": True,
                "context": 1048576,
                "max_tokens": 262144,
                "inputs": ["text", "image"],
                "pi": "openrouter/thinkingmachines/inkling:free",
            }
        ])
        self.assertIn("thinkingmachines/inkling:free", ts)
        self.assertNotIn("stealth/ox-alpha", ts)

    def test_parse_cmd_open_source_and_bans(self) -> None:
        text = """
Available models  ·  4 models

Open Source

deepseek/deepseek-v4-flash             fast hybrid-attention reasoning (default)
meituan/longcat-2.0:free               FREE trillion-parameter agentic coding
poolside/laguna-s-2.1-free             FREE open-weight agentic coding

Anthropic

claude-sonnet-5                        best combo of speed & intelligence
"""
        rows = pick.parse_cmd_list_models(text)
        ids = {r["id"] for r in rows}
        self.assertIn("deepseek/deepseek-v4-flash", ids)
        self.assertIn("meituan/longcat-2.0:free", ids)
        self.assertNotIn("poolside/laguna-s-2.1-free", ids)
        self.assertNotIn("claude-sonnet-5", ids)
        tagged = {r["id"]: r["cmd_free_tag"] for r in rows}
        self.assertTrue(tagged["meituan/longcat-2.0:free"])
        self.assertFalse(tagged["deepseek/deepseek-v4-flash"])
        free_flag = {r["id"]: r["free"] for r in rows}
        self.assertTrue(free_flag["meituan/longcat-2.0:free"])
        self.assertFalse(free_flag["deepseek/deepseek-v4-flash"])

    def test_executor_harnesses_and_reviewer_copy(self) -> None:
        catalog = {
            "deepseek-v4-flash": aa(
                slug="deepseek-v4-flash",
                name="DeepSeek V4 Flash",
                ii=34.53,
            ),
            "glm-5-3-flash": aa(slug="glm-5-3-flash", name="GLM-5.3 Flash", ii=41.91),
            "glm-5-3": aa(slug="glm-5-3", name="GLM-5.3", ii=44.86),
        }
        rows = [
            live(
                catalog="zen",
                id="deepseek-v4-flash-free",
                name="Zen flash",
            ),
            live(
                catalog="hermes",
                id="meituan/longcat-2.0:free",
                name="Nous longcat",
            ),
            live(
                catalog="commandcode",
                id="deepseek/deepseek-v4-flash",
                name="GOAT flash",
                free=False,
            ),
            live(
                catalog="commandcode",
                id="zai-org/glm-5.3",
                name="GOAT glm",
                free=False,
            ),
            live(
                id="z-ai/glm-5.3-flash",
                name="GLM flash",
                pin=0.11,
                pout=0.34,
                free=False,
            ),
        ]
        payload = pick.build_assignment(
            catalog,
            rows,
            "https://artificialanalysis.ai/leaderboards/models",
            now=datetime(2026, 9, 9, 21, 0, tzinfo=timezone.utc),
        )
        free = payload["free"]
        self.assertEqual(free["role"], "executor")
        self.assertEqual(free["pi"], "opencode/deepseek-v4-flash-free")
        self.assertEqual(
            free["harnesses"]["hermes"],
            "hermes -m deepseek-v4-flash-free --provider opencode-free",
        )
        self.assertEqual(free["harnesses"]["cmd"], "cmd -m deepseek/deepseek-v4-flash")
        self.assertNotEqual(free.get("commandcode"), "zai-org/glm-5.3")
        md = pick.render_md(payload)
        self.assertIn("**Reviewer:**", md)
        self.assertIn("muse-code/muse-spark-1.3", md)
        self.assertIn("pi-cursor-sdk", md)
        self.assertIn("cmd -m deepseek/deepseek-v4-flash", md)
        self.assertNotIn("stealth/ox-alpha", md)
        self.assertEqual(
            payload["policy"]["reviewers"],
            ["pi-cursor-sdk (Grok/Composer)", "muse-code/muse-spark-1.3"],
        )

    def test_nous_free_only(self) -> None:
        rows = pick.parse_nous({
            "data": [
                {"id": "anthropic/claude-opus-5"},
                {"id": "meituan/longcat-2.0:free"},
                {"id": "poolside/laguna-s-2.1:free"},
            ]
        })
        ids = {r["id"] for r in rows}
        self.assertEqual(ids, {"meituan/longcat-2.0:free"})


if __name__ == "__main__":
    unittest.main()
