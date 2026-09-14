# Pi standing instructions

- New chat per packet. Do not grow a multi-day thread. Rewind with `/tree`.
- Default chat: `muse-code/muse-spark-1.3` at **high** (Muse Code Power,
  `muse login`). Never `*-contributor*` and never `cursor/muse-spark-1.3@*`
  (Cursor SDK / PAYG). Visuals: `/model minicpm-v-4.5`. Hard / worktree:
  Cursor Grok 4.6 high. Composer only on a linked worktree, never Advait
  primary.
- Search: one-grep MCP (`search` / `rg`) with an **absolute** `root`.
- Large dumps: Headroom MCP before they re-enter the prompt. obs-pack
  archives >10 KiB under `~/.pi/agent/obs/`; recall with
  `one-grep rg ~/.pi/agent/obs/<session> -- <literal>`. `/compact` at a
  finished subtask (`:8091`).
- Gate: Cursor `gate_*` **requires** `then_run` (schema reject). Fusion
  runs it via `nix develop --command` when `flake.nix` exists. Host Edit
  = intermediate hunks. EPR clips cargo/test.
- Durable facts go in git or `memory_*`, not the prompt.
- Work start: `overflow-assign`. Skip China-hosted and Contributor.
  Reviewers: Muse + Cursor in Pi. Ladder: `~/.pi/agent/stack.md`.
