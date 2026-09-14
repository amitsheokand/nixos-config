---
name: herdr-pi-model-spawn
description: Spawn a Herdr pane agent. Pi is the cheap hub; paid Muse Code and Cursor Agent CLI are --kind muse / --kind cursor on a linked worktree. Use when opening a packet seat or when a pane landed on the wrong kind, repo, or /mnt.
---

# Herdr: spawn Pi (cheap) or native CLIs (paid)

Pi is the **cheap** hub (overflow, MiniCPM-V, `/compact`, obs-pack, EPR).
Paid Muse Code Power and Cursor Agent CLI (Ultra / Grok / Composer) are
**`--kind muse`** and **`--kind cursor`** — not `pi-muse-bridge` /
`pi-cursor-sdk`. `--kind grok` is the xAI `grok` CLI; never that.

Worktrees live under **`~/work/worktrees/`** on PC (Worktrunk
`{{ repo_path }}/../worktrees/{{ branch | sanitize }}`). Not `/mnt/`.

## Canonical path (one copy)

This skill is **only** `~/.pi/agent/skills/herdr-pi-model-spawn/SKILL.md`
(Pi user skills; `auto`). Home Manager installs it from this file
(`nixos-config/modules/shared/herdr-pi-worktree/SKILL.md`).

Do **not** `skill_manage create` / `update` this name. That writes a second
copy under `~/.pi/agent/pi-hermes-memory/skills/`. Pi then warns
`[Skill conflicts]` and skips the Hermes copy. Patch **this** file, copy
onto the user-skills path for the current session, then `home-manager switch`.

Pi load order (first wins): `~/.pi/agent/skills/` → packages →
`pi-hermes-memory/skills/`. Same `name` in two trees is a collision.

## Kinds vs models

| Want | Start this | Do not |
|------|------------|--------|
| Cheap / VL / compact / overflow | `--kind pi` (plugin default) | wrapping Ultra or Muse Power inside Pi |
| Muse Code Power | `--kind muse` on a **worktree** | `pi-muse-bridge`, `/model muse-code/*`, `*-contributor*` |
| Cursor Agent CLI (Ultra / Grok / Composer) | `--kind cursor` on a **worktree** | `pi-cursor-sdk`, `/model cursor/*` on a primary, `--kind grok` |
| xAI grok CLI | never | `--kind grok` |

Plugin auto-start (`nixos-config.pi-worktree` on `worktree.opened`):
`--kind pi`. Coordinator `/quit`s that Pi and starts `--kind muse` or
`--kind cursor` for a paid packet. Never those kinds on `~/work/advait` or
`~/work/herdr-lane` primary (`.git/` directory).

## Procedure

### 0. Seat

```bash
test "${HERDR_ENV:-}" = 1
printf 'ws=%s pane=%s pwd=%s\n' "$HERDR_WORKSPACE_ID" "$HERDR_PANE_ID" "$PWD"
herdr workspace list
```

`herdr worktree *` without `--cwd` uses this workspace's git source. A pane
labeled `advait` can still have `checkout_path` = `nixos-config`. Always pass
`--cwd /home/amitsheokand/work/advait` for Advait trees. A packet seat's
`checkout_path` should equal the `wt` path.

### 1. Create the tree (Worktrunk, not git, not herdr create)

```bash
code=/home/amitsheokand/work/advait
packet=tray-island-present   # example
wt -C "$code" switch --create -y -b main "wt/pc/advait/${packet}"
wt -C "$code" list
```

**Pass:** Path is `/home/amitsheokand/work/worktrees/wt-pc-advait-<packet>`.
**Fail:** Path under `/mnt/advait-scratch/`. Do not keep creating there.

### 2. Open in Herdr (fires Pi plugin)

```bash
wt_path=/home/amitsheokand/work/worktrees/wt-pc-advait-${packet}
herdr worktree open \
  --cwd /home/amitsheokand/work/advait \
  --path "$wt_path" \
  --label "T-${packet}" \
  --no-focus
```

Do **not** `herdr workspace create --cwd` as a substitute. `new_cwd=follow`
inherits the previous pane directory; Pi then starts on the wrong repo.

### 3. Confirm default Pi

```bash
herdr agent list
```

Need `agent=pi`, `cwd` == `$wt_path`, live `name` matching `[a-z][a-z0-9_-]{0,31}`.

### 4. Switch model (Grok / Muse Code)

Startup wait only (do not `--wait` a packet):

```bash
name=<from agent list>
pane=<pane_id>
herdr agent wait "$name" --until idle --timeout 60000
herdr agent prompt "$name" "/quit"
# wait until that name is gone and the pane is a shell
# Paid Muse Code (worktree):
herdr agent start "$name" --kind muse --pane "$pane"
# Paid Cursor Agent CLI (worktree only — never Advait/herdr-lane primary):
# herdr agent start "$name" --kind cursor --pane "$pane"
# Cheap Pi (overflow / VL / compact) — keep or restart:
# herdr agent start "$name" --kind pi --pane "$pane"
```

### 5. Verify model and cwd

```bash
herdr agent get "$name"          # .cwd == $wt_path, .agent == muse|cursor|pi
herdr pane process-info --pane "$pane"
herdr agent read "$name" --source visible --lines 20
```

`.agent` must match the kind you started. Pi fullscreen TUI: prefer
`--source visible`. Packet proof is a RECEIPT file in the worktree, not a
nested agent id. Native Cursor/Muse: last hunk+Gate in the same shell;
Headroom before logs re-enter.

### 6. Dispatch PACKET, then idle

```bash
herdr agent prompt "$name" "$(cat "$wt_path/PACKET.md")"
# NO --wait
```

Coordinator must become **idle**. `nixos-config.agent-idle` toasts on named
implementer settle and only `agent prompt`s a coordinator that is already
idle/done (unnamed, or name `coord`/`coordinator`).

## One mux (PC)

Live mux is **`herdr-headless`** (`systemd-run herdr server`, `MemoryMax=8G`).
Do **not** `systemctl --user enable herdr-server` on this host. A second
`herdr server` exits `already running`; `Restart=on-failure` every 5s looks
like a crash. Never add `herdr-server.service.d/direct-server.conf` (that
drop-in bypasses `herdr-serve` wait). PC Home Manager `WantedBy` is empty.

## Do not

- `skill_manage create` this name (second copy under `pi-hermes-memory/skills/`).
- Nested `pi__Agent` / Cursor Task for a packet (parent stays `working`;
  Enter queues as steering because `steeringMode=all`).
- `herdr agent prompt … --wait` from the coordinator for a packet.
- `--kind grok` (xAI CLI). `--kind muse` / `--kind cursor` on a **primary**.
- `/model cursor/*` or `muse-code/*` inside Pi for a paid implementer seat.
- `git worktree add` or `herdr worktree create` as the first create step.
- `git worktree move` across `/mnt` → home (Invalid cross-device link). Copy
  gitignored `PACKET.md` first; `stash -u` skips it.
- Poll implementer panes. Escape aborts and restores the queue; Alt+Up
  retrieves queued text.

## Interrupt vs queue (this pane)

| Key | Effect |
|-----|--------|
| Enter while working | steering queue (delivered after current tools) |
| Alt+Enter | follow-up after the agent finishes |
| Escape | abort; restore queued text to editor |
| Alt+Up | pull queued messages back to editor |
