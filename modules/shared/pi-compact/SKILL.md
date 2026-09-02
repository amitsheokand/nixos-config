---
name: pi-compact-focus
description: >-
  Local Pi context compaction via pi-cc-compact and compact/compactor.
  Use when wiring compact models, diagnosing 503 queue waits, or fine-tuning
  a tiny compact specialist. Never send compact traffic to hipfire.
---

# Pi compact (off hipfire)

Operator (Anvil / forge / Ornith) stays on hipfire `:11435`. Compact is a
different model on a different port.

## Routing

1. Pi `session_before_compact` → `pi-cc-compact` (Claude Code 9-section prompt).
2. `PI_CC_COMPACT_MODEL=compact/compactor` → `127.0.0.1:8091`.
3. Router tries **Mac MLX Compactor** (`ai-mac.local:8081`, `mlx-lane compact`),
   then **local tiny** (`127.0.0.1:8092`, 32k ctx). Oversize prompts are clipped
   to fit. Never `:11435`, the hipfire catalog `:8080` on this PC, or Mac Gemma
   on `:8080`.
4. Router injects `focus.md` and forces thinking off.

If both backends are down, compact returns 503. Do **not** fall back to Anvil
(that is the 30s queue / JSON parse failure).

## Tiny fallback

A small Qwen3.5-0.8B Q8 GGUF on **iGPU Vulkan0** (`127.0.0.1:8092`), never the
R9700. `focus.md` keeps Task/facts. Fine-tune later on Pi compact windows.

GGUF: `~/.local/share/pi-compact/Qwen3.5-0.8B-Q8_0.gguf`

## Commands

- `/compact` — uses compact/compactor, not Anvil.
- Do not `/async-compact-now` on this GPU host (async compact still uses the
  conversation model and will 503 hipfire).
- Hermes flush uses `compact/compactor`, not openai-codex.

## Mac Compactor

Mac serves fused Compactor-Qwen3.5-4B on `:8081` (`enable_thinking=false`, 16k).
The live MLX `/v1/models` list uses the filesystem path
`/Users/amitsheokand/models/Compactor-Qwen3.5-4B-4bit` (alias `compactor` is
not always present). Router rewrites to that path. Exclusive with Gemma:
`mlx-lane compact`.
