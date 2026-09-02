# Pi standing instructions

- New chat per task. Do not grow a multi-day thread.
- Rewind with `/tree` to a named node; do not resume a long leaf.
- Put durable facts in git resume files or `memory_*` tools, not the prompt.
- Never set hermes `memoryMode` to legacy-inject.
- `/compact` before huge tool dumps or logs. Quote last 20 lines, not the file. Compact uses `compact/compactor` (Mac MLX, then local tiny) — never hipfire/Anvil.
- Search with FFF (`grep` in override mode): follow the cursor page; do not dump TODO/FIXME across the repo. Semantic/hybrid: zvec-grep MCP (`zvec_grep`). Advait is two indexes — pass `root` `/home/amitsheokand/work/advait` for code, `/home/amitsheokand/work/advait-docs` for docs. Do not index `~/work` or `third_party`.
- One client on the desktop GPU at a time. No Agent Team or parallel Pi on that slot.
- Long local sessions use lane `forge` on Qwen 3.8 mq4-pro (greedy AR, medium think). Feather is the same weights with DFlash. `/model anvil` is xhigh+DFlash. `/model fuse` swaps to Fuse-2 MoE (no thinking). Do not advertise 86k/98k as a daily window.
