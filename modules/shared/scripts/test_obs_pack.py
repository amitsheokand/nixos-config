#!/usr/bin/env python3
"""Unit tests for obs-pack skip/placeholder. Keep constants in sync with obs-pack.ts."""
from __future__ import annotations

import re
import unittest

THRESHOLD_BYTES = 10 * 1024
FULL_SENDS = 2
HEAD_BYTES = 2048
TAIL_BYTES = 1536
LIKELY_SECRET = re.compile(
    r"(?:api[_-]?key|authorization|bearer|access[_-]?token|secret)[^\n]{0,32}[=:][^\n]+",
    re.I,
)
SKIP_LINE = re.compile(r"^(?:advait_epr_v1|advait_obs_v1)\b")


def should_skip(body: str) -> bool:
    if len(body.encode("utf-8")) <= THRESHOLD_BYTES:
        return True
    if LIKELY_SECRET.search(body):
        return True
    first = body.split("\n", 1)[0]
    return bool(SKIP_LINE.search(first)) or "\nadvait_epr_v1\n" in body


def placeholder_for(body: str, path: str, tool: str = "bash") -> str:
    raw = body.encode("utf-8")
    head = raw[:HEAD_BYTES].decode("utf-8", "replace")
    tail = raw[-TAIL_BYTES:].decode("utf-8", "replace") if len(raw) > TAIL_BYTES else ""
    directory = path.rsplit("/", 1)[0]
    return "\n".join(
        [
            "advait_obs_v1",
            "id=obs_test",
            f"tool={tool}",
            f"source_bytes={len(raw)}",
            f"source_lines={len(body.splitlines())}",
            f"source_artifact={path}",
            f"full_sends={FULL_SENDS}",
            f"recall=one-grep rg {directory} -- <literal>  OR  sed -n '1,80p' {path}",
            "preview_head:",
            head,
            "preview_tail:",
            tail,
        ]
    )


class ObsPackTests(unittest.TestCase):
    def test_skips_small(self) -> None:
        self.assertTrue(should_skip("hello " * 10))

    def test_skips_epr_receipt(self) -> None:
        body = "advait_epr_v1\n" + ("x" * (THRESHOLD_BYTES + 100))
        self.assertTrue(should_skip(body))

    def test_skips_already_packed(self) -> None:
        body = "advait_obs_v1\n" + ("x" * (THRESHOLD_BYTES + 100))
        self.assertTrue(should_skip(body))

    def test_skips_secrets(self) -> None:
        body = "authorization: Bearer sk-live-123\n" + ("x" * (THRESHOLD_BYTES + 100))
        self.assertTrue(should_skip(body))

    def test_packs_large_plain(self) -> None:
        body = "line\n" * 3000
        self.assertGreater(len(body.encode()), THRESHOLD_BYTES)
        self.assertFalse(should_skip(body))

    def test_placeholder_has_onegrep_recall(self) -> None:
        body = "HEAD-MARKER\n" + ("m" * 8000) + "\nTAIL-MARKER\n"
        text = placeholder_for(body, "/tmp/obs/session/obs_test.log")
        self.assertIn("advait_obs_v1", text)
        self.assertIn("one-grep rg", text)
        self.assertIn("HEAD-MARKER", text)
        self.assertIn("TAIL-MARKER", text)
        self.assertNotIn("obs_recall", text)


if __name__ == "__main__":
    unittest.main()
