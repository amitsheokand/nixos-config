#!/usr/bin/env python3
"""Policy tests for Action Fusion. Keep in sync with action-fusion.ts."""
from __future__ import annotations

import json
import re
import unittest


def strip_then_run(params: dict | None) -> tuple[str, dict]:
    rec = dict(params or {})
    raw = rec.pop("then_run", None)
    then_run = raw.strip() if isinstance(raw, str) else ""
    return then_run, rec


def preserve_then_run(prepare, args: dict) -> dict:
    then_run, rest = strip_then_run(args)
    prepared = prepare(rest) if prepare else rest
    rec = dict(prepared) if isinstance(prepared, dict) else dict(rest)
    if then_run:
        rec["then_run"] = then_run
    return rec


def looks_failed(text: str) -> bool:
    t = text.lower()
    if re.search(r"test result:\s*ok", t) or re.search(r"\d+ passed;\s*0 failed", t):
        return False
    return any(
        s in t
        for s in (
            "error",
            "failed",
            "not found",
            "no match",
            "could not find",
            "must be unique",
            "must have required",
        )
    )


def with_then_run_schema(schema: dict, required: bool) -> dict:
    cloned = json.loads(json.dumps(schema))
    cloned.setdefault("properties", {})
    cloned["properties"]["then_run"] = {"type": "string"}
    if required:
        req = list(cloned.get("required") or [])
        if "then_run" not in req:
            req.append("then_run")
        cloned["required"] = req
    return cloned


class FusionPolicyTests(unittest.TestCase):
    def test_prepare_drops_then_run_without_preserve(self) -> None:
        def prepare(args: dict) -> dict:
            return {k: args[k] for k in ("path", "edits") if k in args}

        raw = {
            "path": "src/lib.rs",
            "edits": [{"oldText": "a", "newText": "b"}],
            "then_run": "cargo test --lib",
        }
        dropped = prepare({k: v for k, v in raw.items() if k != "then_run"})
        self.assertNotIn("then_run", dropped)
        kept = preserve_then_run(prepare, raw)
        self.assertEqual(kept["then_run"], "cargo test --lib")
        self.assertEqual(kept["path"], "src/lib.rs")

    def test_gate_schema_requires_then_run(self) -> None:
        schema = with_then_run_schema(
            {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]},
            True,
        )
        self.assertIn("then_run", schema["required"])
        optional = with_then_run_schema({"type": "object", "properties": {}}, False)
        self.assertNotIn("required", optional)

    def test_failed_edit_skips_then_run(self) -> None:
        self.assertTrue(
            looks_failed(
                "Could not find the exact text in src/lib.rs. The old text must match exactly"
            )
        )
        self.assertTrue(looks_failed("Validation failed for tool \"gate_edit\""))
        self.assertFalse(looks_failed("Successfully replaced 1 block(s) in src/lib.rs."))
        self.assertFalse(
            looks_failed(
                "warning: trait Foo should have an upper camel case name\n"
                "test result: ok. 9 passed; 0 failed; 0 ignored\n"
            )
        )
        self.assertTrue(
            looks_failed("error: could not compile `foo` due to previous errors")
        )


if __name__ == "__main__":
    unittest.main()
