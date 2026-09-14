# Pi in Herdr worktrees

Herdr `new_cwd = "follow"` inherits the previous pane directory. Trunkr
opens checkouts with `herdr worktree open --cwd <repo-root> --path <wt-path>`,
which emits `worktree.opened` (not `worktree.created`). This plugin cds the
root pane to the Git checkout, `direnv allow`s a blocked `.envrc`, then
`herdr agent start --kind pi` with OpenCode Zen `nemotron-3-ultra-free`
(cheap hub: overflow, MiniCPM-V, compact).

Paid Muse Code / Cursor Agent CLI are **not** inside Pi. Coordinator
`/quit`s that Pi and starts `--kind muse`, `--kind cursor`, or
`--kind hermes` on a linked worktree. Command Code: plugin action
`nixos-config.pi-worktree.start-cmd` (Herdr has no `--kind cmd`).
Never `--kind grok` (xAI CLI). Never muse/cursor on a primary
checkout (`.git/` directory). Never `cursor/muse-spark-1.3@*` (PAYG) or
`*-contributor*`.

Do **not** `git worktree add` from a coordinator. Create with Worktrunk
(`wt switch --create`, or Herdr `prefix+shift+g`) so hooks run, then let
this plugin start Pi. Do **not** `herdr workspace create --cwd` as a
substitute.

Manual: `prefix+shift+i` or `herdr plugin action invoke start --plugin nixos-config.pi-worktree`.

Companion: `nixos-config.agent-idle` (`herdr-agent-idle/`) toasts and prompts
the idle coordinator when a named implementer settles. Next packet:
`wt switch --create` / `prefix+shift+g` then this plugin auto-starts Pi.
Copy-paste + verify: `~/.pi/agent/skills/herdr-pi-model-spawn/SKILL.md`
(this directory's `SKILL.md`, installed by `pi-agent.nix`). Docs:
`advait-docs/agents/herdr-worktrees.md`. Never `skill_manage create`
`herdr-pi-model-spawn` (duplicate under `pi-hermes-memory/skills/`).
