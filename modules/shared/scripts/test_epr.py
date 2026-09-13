#!/usr/bin/env python3
"""Unit tests for EPR scout/clip/verify. Keep regex in sync with epr.ts."""
from __future__ import annotations

import re
import unittest

DIAGNOSTIC_COMMAND = re.compile(
    r"(?:^|[;&|()\s])(?:cargo(?:\s+(?:build|test|check|nextest))?|cmake\s+--build|"
    r"ctest|ninja|make|pytest|python(?:3)?\s+-m\s+(?:pytest|unittest|py_compile)|"
    r"npm\s+test|pnpm\s+test|yarn\s+test|go\s+test|bazel\s+test)(?:\s|$)",
    re.I,
)
FAILURE_SIGNAL = re.compile(
    r"error|failed|failure|fatal|exception|panic|timeout|unsolved|type mismatch|assert",
    re.I,
)
LIKELY_SECRET = re.compile(
    r"(?:api[_-]?key|authorization|bearer|access[_-]?token|secret)[^\n]{0,32}[=:][^\n]+",
    re.I,
)
MAX_SCOUT_LINES = 12
MAX_QUOTE = 600
CLIP_HEAD = 2048
CLIP_TAIL = 1536


def scout_lines(body: str, max_n: int = MAX_SCOUT_LINES) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for raw in body.splitlines():
        line = raw.rstrip("\n")
        if len(line) < 8 or len(line) > MAX_QUOTE:
            continue
        if not FAILURE_SIGNAL.search(line):
            continue
        if line in seen:
            continue
        seen.add(line)
        out.append(line)
        if len(out) >= max_n:
            break
    return out


def clip_for_llm(body: str, scout: list[str]) -> str:
    head = body[:CLIP_HEAD]
    tail = body[-CLIP_TAIL:] if len(body) > CLIP_TAIL else ""
    extra = [line for line in scout if line not in head and line not in tail]
    parts = [head]
    if extra:
        parts.append("\n".join(extra))
    if tail:
        parts.append(tail)
    return "\n…\n".join(parts)


def quotes_verified(quotes: list[str], body: str) -> bool:
    if not quotes or len(quotes) > MAX_SCOUT_LINES:
        return False
    return all(1 <= len(q) <= MAX_QUOTE and q in body for q in quotes)


class EprTests(unittest.TestCase):
    def test_diagnostic_cargo(self) -> None:
        self.assertTrue(DIAGNOSTIC_COMMAND.search("cargo test -p aikya-com"))
        self.assertTrue(DIAGNOSTIC_COMMAND.search("cargo build --workspace"))
        self.assertFalse(DIAGNOSTIC_COMMAND.search("ls crates"))
        self.assertFalse(DIAGNOSTIC_COMMAND.search("git status"))

    def test_skips_secrets(self) -> None:
        self.assertTrue(LIKELY_SECRET.search("authorization: Bearer sk-live-123"))
        self.assertFalse(LIKELY_SECRET.search("error: missing method release"))

    def test_scout_picks_failure_lines(self) -> None:
        log = (
            "   Compiling aikya-com v0.1.0\n"
            "error[E0599]: no method named `release` found for struct `Holder`\n"
            "   --> crates/aikya/nt/src/holder.rs:88:12\n"
            "error: could not compile `aikya-com` (lib test) due to 1 previous error\n"
            "test result: FAILED. 0 passed; 1 failed; 0 ignored\n"
        )
        scout = scout_lines(log)
        self.assertTrue(any("E0599" in line for line in scout))
        self.assertTrue(any("FAILED" in line for line in scout))
        self.assertTrue(quotes_verified(scout, log))

    def test_rejects_paraphrase(self) -> None:
        log = "error[E0599]: no method named `release` found\n"
        self.assertFalse(quotes_verified(["Holder is missing release()"], log))
        self.assertTrue(
            quotes_verified(
                ["error[E0599]: no method named `release` found"],
                log,
            )
        )

    def test_clip_keeps_middle_scout(self) -> None:
        body = "H" * 3000 + "\nerror: boom in the middle of the log\n" + "T" * 3000
        scout = scout_lines(body, 40)
        clipped = clip_for_llm(body, scout)
        self.assertIn("error: boom in the middle of the log", clipped)
        self.assertLess(len(clipped), len(body))


if __name__ == "__main__":
    unittest.main()
