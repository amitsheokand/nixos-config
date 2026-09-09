#!/usr/bin/env python3
"""Daily free/cheap overflow pick from Artificial Analysis + live catalogs.

Do not pin a model in git. Rank what is actually listed today, write
~/.pi/agent/overflow.{json,md} plus a Pi OpenRouter extension, and reuse
that assignment until the next calendar day (or --refresh).

Free catalogs (executors, not reviewers): OpenRouter, OpenCode Zen,
Hermes (Nous :free + opencode-free), Command-Code GOAT Open Source.
Reviewers stay Cursor Grok / Muse inside Pi.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any

AA_LEADERBOARD = "https://artificialanalysis.ai/leaderboards/models"
AA_FALLBACK = "https://artificialanalysis.ai/models/gpt-oss-120b"
OR_MODELS = "https://openrouter.ai/api/v1/models"
ZEN_MODELS = "https://opencode.ai/zen/v1/models"
NOUS_MODELS = "https://inference-api.nousresearch.com/v1/models"
UA = "overflow-pick/1.0 (nixos-config; +https://artificialanalysis.ai/models)"
CMD_OPEN_SOURCE_END = frozenset(
    {
        "Anthropic",
        "OpenAI",
        "Google",
        "Sakana",
        "Meta",
        "Amazon",
        "Mistral",
        "xAI",
        "Cursor",
    }
)

CHEAP_CAPS = (0.25, 0.50, 1.00)
MIN_CONTEXT = 32_768
VENDOR_PREFIXES = (
    "nvidia-",
    "google-",
    "openai-",
    "cohere-",
    "meta-llama-",
    "meta-",
    "qwen-",
    "deepseek-",
    "mistralai-",
    "mistral-",
    "thinkingmachines-",
    "inclusionai-",
    "z-ai-",
    "zai-org-",
    "zhipu-",
    "meituan-",
    "minimaxai-",
    "minimax-",
    "moonshotai-",
    "stepfun-",
    "tencent-",
    "xiaomi-",
    "sakana-",
)
BAN_SUBSTR = (
    "poolside/",
    "laguna",
    "liquid/",
    "contributor",
    "openrouter/free",
    "openrouter/auto",
    "openrouter/fusion",
    "openrouter/bodybuilder",
    "openrouter/pareto",
    "lyria-",
    "content-safety",
    ":batch",
)


def agent_dir(home: Path | None = None) -> Path:
    return (home or Path.home()) / ".pi" / "agent"


def hermes_dir(home: Path | None = None) -> Path:
    return (home or Path.home()) / ".hermes"


def today_str(now: datetime | None = None) -> str:
    return (now or datetime.now().astimezone()).date().isoformat()


def load_env_file(path: Path) -> None:
    if not path.is_file():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip().strip("'").strip('"')
        if key and key not in os.environ:
            os.environ[key] = val


def http_json(url: str, headers: dict[str, str] | None = None) -> Any:
    hdrs = {"User-Agent": UA, "Accept": "application/json"}
    if headers:
        hdrs.update(headers)
    req = urllib.request.Request(url, headers=hdrs)
    with urllib.request.urlopen(req, timeout=45) as resp:
        return json.load(resp)


def http_text(url: str) -> str:
    req = urllib.request.Request(
        url, headers={"User-Agent": UA, "Accept": "text/html"}
    )
    with urllib.request.urlopen(req, timeout=45) as resp:
        return resp.read().decode("utf-8", "replace")


def extract_obj(src: str, brace_at: int) -> str | None:
    depth = 0
    for j, ch in enumerate(src[brace_at:], brace_at):
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return src[brace_at : j + 1]
    return None


def rsc_blob(html: str) -> str:
    texts: list[str] = []
    for raw in re.findall(r"self\.__next_f\.push\((\[.*?\])\)", html):
        try:
            arr = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if isinstance(arr, list) and len(arr) >= 2 and isinstance(arr[1], str):
            texts.append(arr[1])
    return "".join(texts)


def parse_aa_blob(blob: str) -> dict[str, dict[str, Any]]:
    """Model records with intelligence + context, regardless of key order."""
    best: dict[str, dict[str, Any]] = {}
    for match in re.finditer(r'"slug":"([^"]+)"', blob):
        depth = 0
        start = None
        for j in range(match.start(), -1, -1):
            ch = blob[j]
            if ch == "}":
                depth += 1
            elif ch == "{":
                if depth == 0:
                    start = j
                    break
                depth -= 1
        if start is None:
            continue
        raw = extract_obj(blob, start)
        if not raw:
            continue
        try:
            data = json.loads(raw.replace("undefined", "null"))
        except json.JSONDecodeError:
            continue
        ii = data.get("intelligenceIndex")
        slug = data.get("slug")
        if not slug or not isinstance(ii, (int, float)):
            continue
        if "contextWindowTokens" not in data:
            continue
        rec = {
            "slug": slug,
            "name": data.get("name") or data.get("shortName") or slug,
            "ii": float(ii),
            "pin": data.get("price1mInputTokens"),
            "pout": data.get("price1mOutputTokens"),
            "ctx": data.get("contextWindowTokens"),
            "reasoning": bool(data.get("isReasoning")),
        }
        cur = best.get(slug)
        if cur is None or rec["ii"] > cur["ii"]:
            best[slug] = rec
    return best


def aa_api_key() -> str:
    return (
        os.environ.get("ARTIFICIAL_ANALYSIS_API_KEY")
        or os.environ.get("AA_API_KEY")
        or ""
    ).strip()


def fetch_aa_api() -> dict[str, dict[str, Any]]:
    key = aa_api_key()
    if not key:
        return {}
    best: dict[str, dict[str, Any]] = {}
    page = 1
    while page <= 8:
        payload = http_json(
            f"https://artificialanalysis.ai/api/v2/language/models/free?page={page}",
            headers={"x-api-key": key},
        )
        rows = payload.get("data") or []
        for row in rows:
            slug = row.get("slug")
            ev = row.get("evaluations") or {}
            ii = ev.get("artificial_analysis_intelligence_index")
            if not slug or not isinstance(ii, (int, float)):
                continue
            pricing = row.get("pricing") or {}
            rec = {
                "slug": slug,
                "name": row.get("name") or slug,
                "ii": float(ii),
                "pin": pricing.get("price_1m_input_tokens"),
                "pout": pricing.get("price_1m_output_tokens"),
                "ctx": row.get("context_window") or row.get("contextWindowTokens"),
                "reasoning": bool(row.get("reasoning_model")),
            }
            cur = best.get(slug)
            if cur is None or rec["ii"] > cur["ii"]:
                best[slug] = rec
        pag = payload.get("pagination") or {}
        if not pag.get("has_more"):
            break
        page += 1
    return best


def fetch_aa_html() -> tuple[dict[str, dict[str, Any]], str]:
    last_err: Exception | None = None
    for url in (AA_LEADERBOARD, AA_FALLBACK):
        try:
            html = http_text(url)
            models = parse_aa_blob(rsc_blob(html))
            if len(models) >= 50:
                return models, url
            last_err = RuntimeError(f"{url}: only {len(models)} models")
        except Exception as exc:  # noqa: BLE001 — try next catalog URL
            last_err = exc
    raise RuntimeError(f"Artificial Analysis catalog failed: {last_err}")


def or_million(price: Any) -> float | None:
    try:
        return float(price) * 1_000_000.0
    except (TypeError, ValueError):
        return None


def is_banned(model_id: str) -> bool:
    low = model_id.lower()
    if "~" in low:
        return True
    return any(token in low for token in BAN_SUBSTR)


def is_free_id(model_id: str, prompt_m: float | None, completion_m: float | None) -> bool:
    if ":free" in model_id.lower() or model_id.lower().endswith("-free"):
        return True
    return prompt_m == 0.0 and completion_m == 0.0


def blended(prompt_m: float, completion_m: float) -> float:
    return (3.0 * prompt_m + completion_m) / 4.0


def norm_id(model_id: str) -> str:
    s = model_id.lower().strip()
    s = s.split("/")[-1]
    s = s.split(":")[0]
    s = s.replace(".", "-")
    for suffix in ("-free", "-it", "-instruct"):
        if s.endswith(suffix):
            s = s[: -len(suffix)]
    return s


def id_variants(model_id: str) -> set[str]:
    base = norm_id(model_id)
    out = {base}
    for prefix in VENDOR_PREFIXES:
        if base.startswith(prefix):
            out.add(base[len(prefix) :])
        else:
            out.add(prefix + base)
    return {item for item in out if item}


def match_aa(model_id: str, aa: dict[str, dict[str, Any]]) -> dict[str, Any] | None:
    variants = id_variants(model_id)
    for variant in variants:
        if variant in aa:
            return aa[variant]
    hits: list[str] = []
    for variant in variants:
        for slug in aa:
            if slug == variant or slug.startswith(variant + "-") or variant.startswith(slug + "-"):
                hits.append(slug)
    if not hits:
        return None
    hits = sorted(set(hits), key=lambda slug: (-aa[slug]["ii"], -len(slug)))
    return aa[hits[0]]


def parse_openrouter(payload: Any) -> list[dict[str, Any]]:
    rows = []
    for item in payload.get("data") or []:
        mid = item.get("id") or ""
        if not mid or is_banned(mid):
            continue
        arch = item.get("architecture") or {}
        inputs = [str(x).lower() for x in (arch.get("input_modalities") or ["text"])]
        if "text" not in inputs:
            continue
        ctx = int(item.get("context_length") or 0)
        if ctx < MIN_CONTEXT:
            continue
        pricing = item.get("pricing") or {}
        pin = or_million(pricing.get("prompt"))
        pout = or_million(pricing.get("completion"))
        if pin is None or pout is None or pin < 0 or pout < 0:
            continue
        top = item.get("top_provider") or {}
        params = [str(x) for x in (item.get("supported_parameters") or [])]
        rows.append(
            {
                "catalog": "openrouter",
                "id": mid,
                "name": item.get("name") or mid,
                "ctx": ctx,
                "max_tokens": int(top.get("max_completion_tokens") or min(ctx, 131072)),
                "pin": pin,
                "pout": pout,
                "free": is_free_id(mid, pin, pout),
                "reasoning": "reasoning" in params or "reasoning_effort" in params,
                "inputs": inputs,
            }
        )
    return rows


def parse_zen(payload: Any) -> list[dict[str, Any]]:
    rows = []
    for item in payload.get("data") or []:
        mid = item.get("id") or item.get("model") or ""
        if not mid or is_banned(mid):
            continue
        free = is_free_id(mid, None, None)
        if not free:
            continue
        rows.append(
            {
                "catalog": "zen",
                "id": mid,
                "name": item.get("name") or mid,
                "ctx": int(item.get("context_length") or item.get("limit") or 131072),
                "max_tokens": 32768,
                "pin": 0.0,
                "pout": 0.0,
                "free": True,
                "reasoning": True,
                "inputs": ["text"],
            }
        )
    return rows


def parse_id_list(ids: Any, catalog: str, *, free_only: bool = True) -> list[dict[str, Any]]:
    rows = []
    for item in ids or []:
        mid = item if isinstance(item, str) else (item.get("id") or item.get("model") or "")
        if not mid or is_banned(mid):
            continue
        if free_only and not is_free_id(mid, None, None):
            continue
        rows.append(
            {
                "catalog": catalog,
                "id": mid,
                "name": mid,
                "ctx": 131072,
                "max_tokens": 32768,
                "pin": 0.0,
                "pout": 0.0,
                "free": True,
                "reasoning": True,
                "inputs": ["text"],
            }
        )
    return rows


def parse_nous(payload: Any) -> list[dict[str, Any]]:
    return parse_id_list(payload.get("data") or [], "hermes", free_only=True)


def parse_cmd_list_models(text: str) -> list[dict[str, Any]]:
    """GOAT `cmd --list-models`: Open Source (+ FREE tags) are executor catalogs."""
    rows = []
    in_open = False
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("Available models") or line.startswith("Updated "):
            continue
        if line in {"Open Source", "Open-Source"}:
            in_open = True
            continue
        if line in CMD_OPEN_SOURCE_END:
            in_open = False
            continue
        if not in_open:
            continue
        mid, _, desc = line.partition(" ")
        mid = mid.strip()
        desc = desc.strip()
        if not mid or is_banned(mid):
            continue
        if "/" not in mid and ":" not in mid:
            continue
        tagged_free = "FREE" in desc or is_free_id(mid, None, None)
        rows.append(
            {
                "catalog": "commandcode",
                "id": mid,
                "name": mid,
                "ctx": 131072,
                "max_tokens": 32768,
                "pin": 0.0,
                "pout": 0.0,
                "free": tagged_free,
                "reasoning": True,
                "inputs": ["text"],
                "cmd_free_tag": tagged_free,
            }
        )
    return rows


def nous_auth(home: Path) -> tuple[str | None, str]:
    path = hermes_dir(home) / "auth.json"
    if not path.is_file():
        return None, NOUS_MODELS
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None, NOUS_MODELS
    nous = (payload.get("providers") or {}).get("nous") or {}
    token = nous.get("access_token") or nous.get("agent_key")
    base = str(nous.get("inference_base_url") or "https://inference-api.nousresearch.com/v1")
    return (str(token) if token else None), base.rstrip("/") + "/models"


def fetch_nous_free(home: Path) -> list[dict[str, Any]]:
    token, url = nous_auth(home)
    if token:
        try:
            req = urllib.request.Request(
                url,
                headers={"User-Agent": UA, "Authorization": f"Bearer {token}"},
            )
            with urllib.request.urlopen(req, timeout=20) as resp:
                payload = json.loads(resp.read().decode("utf-8", errors="replace"))
            rows = parse_nous(payload)
            if rows:
                return rows
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
            pass
    cache_path = hermes_dir(home) / "provider_models_cache.json"
    if not cache_path.is_file():
        return []
    try:
        cache = json.loads(cache_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []
    return parse_id_list((cache.get("nous") or {}).get("models"), "hermes", free_only=True)


def fetch_cmd_models() -> list[dict[str, Any]]:
    cmd = shutil.which("cmd")
    if not cmd:
        return []
    try:
        proc = subprocess.run(
            [cmd, "--list-models"],
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    return parse_cmd_list_models((proc.stdout or "") + "\n" + (proc.stderr or ""))


def attach_aa(rows: list[dict[str, Any]], aa: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    out = []
    for row in rows:
        hit = match_aa(row["id"], aa)
        if hit is None:
            continue
        rec = dict(row)
        rec["aa"] = hit
        rec["ii"] = hit["ii"]
        out.append(rec)
    return out


def rank(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return sorted(rows, key=lambda r: (-r["ii"], r["pin"] + r["pout"], r["id"]))


def pick_free(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return rank([r for r in rows if r["free"]])


def pick_cheap(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    paid = [r for r in rows if not r["free"] and r["catalog"] == "openrouter"]
    for cap in CHEAP_CAPS:
        hits = [r for r in paid if blended(r["pin"], r["pout"]) <= cap]
        if hits:
            return rank(hits)
    return rank(paid)


def catalog_row(alts: list[dict[str, Any]], name: str) -> dict[str, Any] | None:
    return next((a for a in alts if a["catalog"] == name), None)


def harnesses_for(alts: list[dict[str, Any]]) -> dict[str, str | None]:
    zen = catalog_row(alts, "zen")
    orow = catalog_row(alts, "openrouter")
    hermes = catalog_row(alts, "hermes")
    cmd = catalog_row(alts, "commandcode")
    pi = None
    if zen:
        pi = f"opencode/{zen['id']}"
    elif orow and orow.get("free"):
        pi = f"openrouter/{orow['id']}"
    hermes_cmd = None
    if hermes:
        hermes_cmd = f"hermes -m {hermes['id']} --provider nous"
    elif zen:
        hermes_cmd = f"hermes -m {zen['id']} --provider opencode-free"
    return {
        "pi": pi,
        "hermes": hermes_cmd,
        "cmd": f"cmd -m {cmd['id']}" if cmd else None,
    }


def route_card(row: dict[str, Any], alts: list[dict[str, Any]]) -> dict[str, Any]:
    zen = catalog_row(alts, "zen")
    orow = catalog_row(alts, "openrouter") or row
    hermes = catalog_row(alts, "hermes")
    cmd = catalog_row(alts, "commandcode")
    harnesses = harnesses_for(alts)
    paid = (not row.get("free")) and orow.get("catalog") == "openrouter"
    if paid:
        preferred = orow
        provider = "openrouter"
        pi = f"openrouter/{orow['id']}"
        confidential = True
        note = "Cheap paid API. Prefer this over :free for private packets."
        harnesses = {"pi": pi, "hermes": None, "cmd": None}
    elif zen:
        preferred = zen
        provider = "opencode"
        pi = harnesses["pi"]
        confidential = False
        note = "Free / included executor: not a reviewer; not for confidential packets."
    elif orow.get("catalog") == "openrouter":
        preferred = orow
        provider = "openrouter"
        pi = harnesses["pi"] or f"openrouter/{orow['id']}"
        confidential = not preferred["free"]
        note = (
            "Free / included executor: not a reviewer; not for confidential packets."
            if preferred["free"]
            else "Cheap paid API. Prefer this over :free for private packets."
        )
    elif hermes:
        preferred = hermes
        provider = "hermes"
        pi = harnesses["pi"]
        confidential = False
        note = "Free / included executor: not a reviewer; not for confidential packets."
    elif cmd:
        preferred = cmd
        provider = "commandcode"
        pi = harnesses["pi"]
        confidential = False
        note = "Free / included executor: not a reviewer; not for confidential packets."
    else:
        preferred = row
        provider = str(row.get("catalog") or "unknown")
        pi = harnesses["pi"]
        confidential = not preferred.get("free", True)
        note = "Free / included executor: not a reviewer; not for confidential packets."
    return {
        "pi": pi,
        "provider": provider,
        "model": preferred["id"],
        "openrouter": orow["id"] if orow.get("catalog") == "openrouter" else None,
        "zen": zen["id"] if zen else None,
        "hermes": hermes["id"] if hermes else None,
        "commandcode": cmd["id"] if cmd else None,
        "harnesses": harnesses,
        "name": preferred["aa"]["name"],
        "aa_slug": preferred["aa"]["slug"],
        "aa_intelligence": round(preferred["ii"], 2),
        "context": preferred.get("ctx") or orow.get("ctx"),
        "usd_per_m_in": round(orow["pin"], 4) if orow.get("catalog") == "openrouter" else 0.0,
        "usd_per_m_out": round(orow["pout"], 4) if orow.get("catalog") == "openrouter" else 0.0,
        "confidential_ok": confidential,
        "note": note,
        "reasoning": bool(preferred.get("reasoning") or orow.get("reasoning")),
        "max_tokens": orow.get("max_tokens") or 32768,
        "inputs": orow.get("inputs") or ["text"],
        "role": "cheap-paid" if paid else "executor",
    }


def group_same_model(ranked: list[dict[str, Any]]) -> list[list[dict[str, Any]]]:
    """Cluster rows that matched the same AA slug."""
    groups: dict[str, list[dict[str, Any]]] = {}
    order: list[str] = []
    for row in ranked:
        slug = row["aa"]["slug"]
        if slug not in groups:
            groups[slug] = []
            order.append(slug)
        groups[slug].append(row)
    return [groups[slug] for slug in order]


def merge_catalogs(group: list[dict[str, Any]], ranked: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Add sibling harness rows (e.g. GOAT Open Source) for the same AA slug."""
    slug = group[0]["aa"]["slug"]
    merged: list[dict[str, Any]] = []
    seen: set[str] = set()
    for row in group + [r for r in ranked if r["aa"]["slug"] == slug]:
        if row["catalog"] in seen:
            continue
        seen.add(row["catalog"])
        merged.append(row)
    return merged


def or_js_model(card: dict[str, Any]) -> dict[str, Any] | None:
    mid = card.get("openrouter")
    if not mid:
        return None
    inputs = ["text"]
    if "image" in (card.get("inputs") or []):
        inputs.append("image")
    thinking = None
    if card.get("reasoning"):
        thinking = {
            "off": None,
            "minimal": "low",
            "low": "low",
            "medium": "medium",
            "high": "high",
            "xhigh": "high",
            "max": "max",
        }
    per_tok_in = 0.0 if not card.get("confidential_ok") else card["usd_per_m_in"] / 1_000_000.0
    per_tok_out = 0.0 if not card.get("confidential_ok") else card["usd_per_m_out"] / 1_000_000.0
    spec = {
        "id": mid,
        "name": f"{card['name']} (overflow)",
        "reasoning": bool(card.get("reasoning")),
        "input": inputs,
        "cost": {
            "input": per_tok_in,
            "output": per_tok_out,
            "cacheRead": 0,
            "cacheWrite": 0,
        },
        "contextWindow": int(card.get("context") or 128000),
        "maxTokens": int(card.get("max_tokens") or 32768),
        "compat": {
            "thinkingFormat": "openrouter",
            "supportsReasoningEffort": bool(card.get("reasoning")),
            "maxTokensField": "max_tokens",
            "supportsDeveloperRole": False,
        },
    }
    if thinking is not None:
        spec["thinkingLevelMap"] = thinking
    return spec


def render_extension(cards: list[dict[str, Any]]) -> str:
    models = []
    seen: set[str] = set()
    for card in cards:
        spec = or_js_model(card)
        if spec is None or spec["id"] in seen:
            continue
        seen.add(spec["id"])
        models.append(spec)
    models_js = json.dumps(models, indent=2)
    return f"""// Generated by overflow-pick. Do not edit.
// Re-run `overflow-assign --refresh` to replace today's OpenRouter overflow models.

import type {{ ExtensionAPI }} from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {{
  pi.registerProvider("openrouter", {{
    name: "OpenRouter",
    baseUrl: "https://openrouter.ai/api/v1",
    apiKey: "$OPENROUTER_API_KEY",
    api: "openai-completions",
    headers: {{
      "X-Title": "pi",
      "HTTP-Referer": "https://openrouter.ai",
    }},
    models: {models_js},
  }});
}}
"""


def render_md(payload: dict[str, Any]) -> str:
    free = payload.get("free")
    cheap = payload.get("cheap")
    lines = [
        f"# Overflow assignment ({payload['date']})",
        "",
        "Assigned at work start. **Do not re-rank** and do not scrape",
        "[Artificial Analysis](https://artificialanalysis.ai/models) again today.",
        "Scores: Artificial Analysis Intelligence Index (public catalog).",
        "",
        "## Roles",
        "",
        "- **Executor:** today's free pick — any of Pi (OpenRouter / OpenCode Zen),",
        "  `hermes`, or `cmd`. Local default is still `longctx`.",
        "- **Reviewer:** Cursor Grok / Composer and Muse **in Pi**. Do not review",
        "  with the free overflow model.",
        "",
    ]
    if free:
        harnesses = free.get("harnesses") or {}
        lines += [
            "## Executor (free / included)",
            "",
            f"- Pi: `{harnesses.get('pi') or free.get('pi') or '—'}`",
            f"- Hermes: `{harnesses.get('hermes') or '—'}`",
            f"- Command-Code: `{harnesses.get('cmd') or '—'}`",
            f"- AA: {free['aa_intelligence']} (`{free['aa_slug']}`)",
            f"- {free['note']}",
            "",
        ]
    else:
        lines += ["## Executor (free / included)", "", "No AA-ranked free model was listed today.", ""]
    lines += [
        "## Reviewer (Pi, not free overflow)",
        "",
        "- Muse: `muse-code/muse-spark-1.3` or subagent `muse-spark`",
        "- Cursor: `pi-cursor-sdk` (Grok / Composer) or Cursor Ultra in the IDE",
        "",
    ]
    if cheap:
        lines += [
            "## Cheap paid (private-ok)",
            "",
            f"- Pi: `{cheap['pi']}`",
            f"- AA: {cheap['aa_intelligence']} (`{cheap['aa_slug']}`)",
            f"- ${cheap['usd_per_m_in']}/${cheap['usd_per_m_out']} per 1M in/out",
            f"- {cheap['note']}",
            "",
        ]
    else:
        lines += ["## Cheap paid", "", "No cheap AA-ranked API was listed today.", ""]
    lines += [
        "Privacy: skip China-hosted endpoints and share-by-default / Contributor plans.",
        "",
    ]
    return "\n".join(lines)


def merge_same_aa(
    groups: list[list[dict[str, Any]]],
    ranked: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    cards = []
    pool = ranked or []
    for group in groups[:8]:
        alts = merge_catalogs(group, pool) if pool else group
        cards.append(route_card(group[0], alts))
    return cards


def build_assignment(
    aa: dict[str, dict[str, Any]],
    live: list[dict[str, Any]],
    aa_url: str,
    now: datetime | None = None,
) -> dict[str, Any]:
    stamped = now or datetime.now().astimezone()
    ranked = attach_aa(live, aa)
    free_cards = merge_same_aa(group_same_model(pick_free(ranked)), ranked)
    cheap_cards = merge_same_aa(group_same_model(pick_cheap(ranked)), ranked)
    free = free_cards[0] if free_cards else None
    cheap = next((c for c in cheap_cards if c.get("openrouter") != (free or {}).get("openrouter")), None)
    if cheap is None and cheap_cards:
        cheap = cheap_cards[0]
    return {
        "date": today_str(stamped),
        "assigned_at": stamped.isoformat(timespec="seconds"),
        "source": {
            "artificial_analysis": aa_url,
            "attribution": "Artificial Analysis",
            "openrouter": OR_MODELS,
            "zen": ZEN_MODELS,
            "hermes_nous": NOUS_MODELS,
            "commandcode": "cmd --list-models",
        },
        "policy": {
            "cheap_blended_usd_per_m": list(CHEAP_CAPS),
            "min_context": MIN_CONTEXT,
            "free_confidential_ok": False,
            "banned_substrings": list(BAN_SUBSTR),
            "executor_catalogs": ["openrouter", "zen", "hermes", "commandcode"],
            "reviewers": ["pi-cursor-sdk (Grok/Composer)", "muse-code/muse-spark-1.3"],
        },
        "free": free,
        "cheap": cheap,
        "runners_up": {
            "free": free_cards[1:4],
            "cheap": cheap_cards[1:4],
        },
    }


def write_assignment(payload: dict[str, Any], dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    json_path = dest / "overflow.json"
    md_path = dest / "overflow.md"
    ext_dir = dest / "extensions"
    ext_dir.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    md_path.write_text(render_md(payload), encoding="utf-8")
    cards = [c for c in (payload.get("free"), payload.get("cheap")) if c]
    for extra in (payload.get("runners_up") or {}).get("free", []):
        cards.append(extra)
    for extra in (payload.get("runners_up") or {}).get("cheap", []):
        cards.append(extra)
    (ext_dir / "openrouter-overflow.ts").write_text(
        render_extension(cards), encoding="utf-8"
    )


def load_today(dest: Path, now: datetime | None = None) -> dict[str, Any] | None:
    path = dest / "overflow.json"
    if not path.is_file():
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    if payload.get("date") != today_str(now):
        return None
    if not payload.get("free") and not payload.get("cheap"):
        return None
    return payload


def fetch_live(home: Path | None = None) -> list[dict[str, Any]]:
    home = home or Path.home()
    rows: list[dict[str, Any]] = []
    try:
        rows.extend(parse_openrouter(http_json(OR_MODELS)))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
        pass
    try:
        rows.extend(parse_zen(http_json(ZEN_MODELS)))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
        cache_path = hermes_dir(home) / "provider_models_cache.json"
        if cache_path.is_file():
            try:
                cache = json.loads(cache_path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                cache = {}
            rows.extend(
                parse_id_list(
                    (cache.get("opencode-free") or {}).get("models"),
                    "zen",
                    free_only=True,
                )
            )
    rows.extend(fetch_nous_free(home))
    rows.extend(fetch_cmd_models())
    return rows


def refresh(dest: Path, home: Path | None = None) -> dict[str, Any]:
    root = home or Path.home()
    load_env_file(root / ".config" / "openrouter.env")
    load_env_file(root / ".config" / "artificialanalysis.env")
    aa_url = AA_LEADERBOARD
    aa = fetch_aa_api()
    if aa:
        aa_url = "https://artificialanalysis.ai/api/v2/language/models/free"
    else:
        aa, aa_url = fetch_aa_html()
    payload = build_assignment(aa, fetch_live(root), aa_url)
    write_assignment(payload, dest)
    return payload


def print_assignment(payload: dict[str, Any], as_json: bool) -> None:
    if as_json:
        json.dump(payload, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return
    text = render_md(payload)
    sys.stdout.write(text if text.endswith("\n") else text + "\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Assign today's free/cheap overflow model; do not re-research."
    )
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="Re-rank from AA + live catalogs even if today is already assigned.",
    )
    parser.add_argument("--json", action="store_true", help="Print overflow.json.")
    parser.add_argument(
        "--home",
        type=Path,
        default=None,
        help="Override home (tests).",
    )
    args = parser.parse_args(argv)
    dest = agent_dir(args.home)
    dest.mkdir(parents=True, exist_ok=True)
    payload = None if args.refresh else load_today(dest)
    if payload is None:
        try:
            payload = refresh(dest, args.home)
        except Exception as exc:  # noqa: BLE001 — keep yesterday rather than fail the day
            stale = dest / "overflow.json"
            if stale.is_file():
                print(f"overflow-pick: refresh failed ({exc}); keeping previous assignment", file=sys.stderr)
                payload = json.loads(stale.read_text(encoding="utf-8"))
            else:
                print(f"overflow-pick: {exc}", file=sys.stderr)
                return 1
    print_assignment(payload, args.json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
