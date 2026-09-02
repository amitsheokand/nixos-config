# Pi standing instructions

- New chat per task. Do not grow a multi-day thread.
- Rewind with `/tree` to a named node; do not resume a long leaf.
- Put durable facts in git resume files or `memory_*` tools, not the prompt.
- Never set hermes `memoryMode` to legacy-inject.
- `/compact` before huge tool dumps or logs. Quote last 20 lines, not the file. Compact uses `compact/compactor` (Mac MLX, then local tiny) — never hipfire/Anvil.
- Search with FFF (`grep` in override mode): follow the cursor page; do not dump TODO/FIXME across the repo.
- One client on the desktop GPU at a time. No Agent Team or parallel Pi on that slot.
- Long local sessions use lane `forge` on Qwen 3.8 mq4-pro. Feather is the same weights with DFlash. `/model ornith` or `/model forge/ornith` swaps to Ornith MQ4R. Do not advertise 86k/98k as a daily window.
