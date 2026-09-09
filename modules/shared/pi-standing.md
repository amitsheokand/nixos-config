# Pi standing instructions

- New chat per task. Do not grow a multi-day thread.
- Rewind with `/tree` to a named node; do not resume a long leaf.
- Put durable facts in git resume files or `memory_*` tools, not the prompt.
- Never set hermes `memoryMode` to legacy-inject.
- `/compact` before huge tool dumps or logs. Quote last 20 lines, not the file. Compact uses `compact/compactor` (Mac MLX, then local tiny) — never hipfire/Anvil.
- Search with FFF (`grep` in override mode): follow the cursor page; do not dump TODO/FIXME across the repo. Semantic/hybrid: zvec-grep MCP (`zvec_grep`).
- One client on the desktop GPU at a time. No Agent Team or parallel Pi on that slot.
- Default local model is `longctx` (MiniCPM5-2B on the Mac). Escalate to `forge` / `anvil` on Qwen 3.8 only when the packet needs it. Usage ladder: `~/.pi/agent/stack.md`.
- At work start: `overflow-assign`. Use `~/.pi/agent/overflow.md` for the free
  **executor** (Pi OpenRouter/Zen, `hermes`, or `cmd`). Do not re-rank or scrape
  Artificial Analysis during the session. Do not use that free model as a reviewer.
- Reviewers: Muse in Pi (`muse-code/muse-spark-1.3` or subagent `muse-spark`) and
  Cursor Grok / Composer (`pi-cursor-sdk`). Never Meta Model API PAYG (`MODEL_API_KEY`).
