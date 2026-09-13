# Pi standing instructions

- New chat per packet. Do not grow a multi-day thread. Rewind with `/tree`.
- Default chat: `cursor/composer-2-5:slow` at **high** (Cursor Ultra). Not
  `:fast`. Not MiniCPM5 `longctx` (parked — too slow). Visuals:
  `/model minicpm-v-4.5`. From 14 Sep: Bounded PE + review via
  `muse-code/muse-spark-1.3` (never `*-contributor*`). Hard: Grok 4.6 high.
- Search: one-grep MCP (`search` / `rg`) with an **absolute** `root`
  (code checkout vs docs clone). FFF `grep` pages; do not dump TODO/FIXME.
- Large tool output: Headroom MCP (`headroom_compress`) **before** it re-enters
  the prompt. On Pi, obs-pack archives dumps >10 KiB under `~/.pi/agent/obs/`;
  recall with `one-grep rg ~/.pi/agent/obs/<session> -- <literal>`. Do not
  call `obs_recall`. `/compact` at a finished subtask (`compact/compactor` on
  `:8091` → Mac `:8081` then iGPU `:8092`). Never compact on hipfire. Do not
  treat blunt early compact as a substitute for a new chat.
- After `edit`/`write`, if you would immediately bash a test/build/check of
  that file, pass `then_run` on the same call (Action Fusion). PACKET.md
  **Gate** is the default command. Long `cargo test` / cmake logs are reduced
  locally (EPR: scout, then `compact/compactor` ~8k-token clip). Read
  `source_artifact` when you need the full log. Logs never leave the LAN.
- Durable facts go in git resume files or `memory_*` tools, not the prompt.
  Never hermes `memoryMode` legacy-inject.
- At work start: `overflow-assign`. Use `~/.pi/agent/overflow.md` only if the
  pick is **not** China-hosted and **not** Contributor. Ignore a DeepSeek /
  Z.AI / Kimi / Alibaba first-party id. Reviewers: Muse + Cursor in Pi.
- One client on the desktop GPU at a time (MiniCPM-V). Usage ladder:
  `~/.pi/agent/stack.md`.
