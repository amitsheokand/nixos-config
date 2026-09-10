# Pi in Herdr worktrees

Herdr `new_cwd = "follow"` inherits the previous pane directory. Trunkr
opens checkouts with `herdr worktree open`, which emits `worktree.opened`
(not `worktree.created`). This plugin cds the root pane to the Git checkout,
`direnv allow`s a blocked `.envrc`, then `herdr agent start --kind pi`.

Do **not** `git worktree add` from a coordinator. Create with Worktrunk
(`wt switch --create`, or Herdr `prefix+shift+g`) so hooks run, then let
this plugin start Pi.

Manual: `prefix+shift+i` or `herdr plugin action invoke start --plugin nixos-config.pi-worktree`.

Companion: `nixos-config.agent-idle` (`herdr-agent-idle/`) toasts and prompts
the idle coordinator when a named implementer settles. Next packet:
`wt switch --create` / `prefix+shift+g` then this plugin auto-starts Pi.
