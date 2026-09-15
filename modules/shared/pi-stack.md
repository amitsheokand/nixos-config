# Pi hub — usage ladder

Pi is the **cheap** hub inside Herdr panes (overflow, MiniCPM-V, `/compact`,
obs-pack, EPR). Default chat is OpenCode Zen `nemotron-3-ultra-free`. Paid
Muse Code and Cursor Agent CLI are **`--kind muse`** and **`--kind cursor`**
on a linked worktree — never `pi-muse-bridge` / `pi-cursor-sdk`, never
`/model muse-code/*` or `/model cursor/*` inside Pi. Create/open worktrees
with **Worktrunk + trunkr** (`prefix+shift+g` / `wt switch --create`), never
`git worktree add`. The `nixos-config.pi-worktree` plugin cds the pane and
starts `--kind pi`. Coordinator `/quit`s and starts the native kind for a
paid packet. Do not open a second control plane for the same work.

Public writeup in nixos-config: `docs/coding-agent-stack.md`.

Pipeline that must stay wired (thin harness; do not bloat the system prompt):

| Layer | Job | Where |
|-------|-----|--------|
| Herdr | panes, worktrees, idle notify | `herdr.nix` + `wt`. PC mux = `herdr-headless`, not `herdr-server` |
| Pi | four tools + extensions | `pi-agent.nix` |
| one-grep | hybrid search, absolute `root` | MCP **on** Pi / Cursor / Muse / Hermes (not a Pi wrap) |
| Headroom | compress tool dumps before they re-enter context | MCP on Pi + Cursor; proxy `:8787` for Claude/Codex |
| Compactor | session compact at subtask boundaries | `:8091` → Mac `:8081` → iGPU `:8092` |
| Action Fusion | `then_run` on edit/write **and** `gate_edit`/`gate_write` | `pi-extensions/action-fusion.ts` (`--kind pi` only) |
| EPR | diagnostic logs → scout, then local Compactor | `pi-extensions/epr.ts` (`--kind pi` only) |
| obs-pack | large tool results → archive + head/tail after 2 sends | `pi-extensions/obs-pack.ts` (`--kind pi` only) |

Do **not** install NVIDIA SoL-Pi as a second package. It is a Pi
extension, not a harness, but two of its four mechanisms duplicate this
ladder:

| SoL-Pi | Ours | Action |
|--------|------|--------|
| Action Fusion | none before | **brought over** as `action-fusion.ts` |
| ObservationPack | Headroom + **obs-pack.ts** on Pi | 10 KiB, 2 full sends, then head/tail; recall via one-grep / sed. Not `obs_recall`. |
| Online Context Compact | `/compact` + `pi-cc-compact` + `pi-async-compaction` | do not enable OCC (it aborts the run) |
| Evidence-Preserving Reducer | local scout + `compact/compactor` (12k-token clip) | **brought over** as `epr.ts` (no cloud) |

Grok Bot is quota-capped. [Rakazo](https://github.com/elie222/rakazo) is the
open-source persistent-bot UI (also Pi-backed). It is **not** wired here —
use Pi + this ladder until a persistent-bot UI is an explicit install.

At the start of a workday run `overflow-assign` (no `--refresh` unless the
file is missing). That writes today's free/cheap pick to
`~/.pi/agent/overflow.md`. Do not scrape
[Artificial Analysis](https://artificialanalysis.ai/models) again in the
session. Free picks are **executors** (OpenRouter, OpenCode Zen, Hermes,
Command-Code) **US-hosted only**. Reviewers are `--kind muse` or
`--kind cursor` on a worktree, not overflow, not a Pi `/model`.

## Pick a model (cheap first)

| Need | Where | Notes |
|------|-------|--------|
| Coordinator, boards, mechanical | Pi `--kind pi` + Zen `nemotron-3-ultra-free` | Not a paid wrap. Not Contributor. |
| Visual / screenshot | Pi `/model minicpm-v-4.5` | Discrete GPU `:8093`. Do not paste PNGs. |
| Session compact | `/compact` → `compact/compactor` | Mac `:8081` then iGPU `:8092`. |
| Free / included cloud executor | today's `~/.pi/agent/overflow.md` | Pi Zen, Hermes Nous OSS, `cmd` GOAT OSS. Not a reviewer. |
| Hermes quality (GPT-5/Claude portal) | `--kind hermes` (worktree) | $20 plan default — not overflow |
| Command Code GOAT | plugin `start-cmd` / `cmd --yolo --trust` | Herdr has no `--kind cmd` |
| Reviewer (frozen diff) | `--kind muse` or `--kind cursor` (worktree) | Never the free overflow model. Never Contributor. |
| Paid Muse Code | `--kind muse` (worktree) | never `pi-muse-bridge` |
| Paid Cursor Agent CLI | `--kind cursor` (worktree) **high**; xhigh if labeled Hard | never `pi-cursor-sdk`; never `--kind grok` |
| Parked | MiniCPM5-2B longctx `:8080`; hipfire 27B | Too slow / Conflicts with MiniCPM-V. |

## Spawn that model in a Herdr pane

Copy-paste + verify: `~/.pi/agent/skills/herdr-pi-model-spawn/SKILL.md`
(source: `modules/shared/herdr-pi-worktree/SKILL.md`). That Nix copy is
the pin. Do **not** `skill_manage create` that name — Hermes memory writes
a second copy under `~/.pi/agent/pi-hermes-memory/skills/` and Pi reports
`[Skill conflicts]`. Ignore the memory-dir copy.

1. `wt -C <primary> switch --create -y -b main wt/<host>/<repo>/<packet>`
   → path **must** be under `~/work/worktrees/` on the PC (not `/mnt/`).
2. `herdr worktree open --cwd <primary> --path <wt-path> --label T-<id> --no-focus`
   (always `--cwd` the primary clone; workspace label can lie).
3. Plugin starts `--kind pi` (cheap). For a paid packet: `/quit`, then
   `herdr agent start <name> --kind muse --pane <id>` or `--kind cursor`
   (worktree only; plugin passes `--workspace`). Never `--kind grok`. Never
   those kinds on a primary. Paid seats use Headroom + one-grep (worktree
   `root`) + one shell after edit — not Fusion/EPR/obs-pack.
4. Verify `herdr agent get` cwd and `.agent`. Prompt PACKET **without**
   `--wait`. Coordinator stays idle.

`--kind grok` is the xAI `grok` CLI — never. Nested `pi__Agent` blocks the
coordinator; user Enter queues (`steeringMode=all`).

## Privacy

- No China-hosted cloud endpoints.
- No share-by-default / Contributor plans.
- Local weights on our machines are fine (any origin).
- GLM / Qwen / DeepSeek cloud OK only when the **host** is outside China.
  `overflow-pick.py` bans first-party China catalog ids.

## Mac MLX lanes (`mlx-lane`)

- `minicpm` / `longctx` — parked chat on `:8080`; may share RAM with compact `:8081`
- `compact` — `:8081` Compactor 4B (Pi `/compact` only)
- `gemma` — 12B coder, exclusive (stops MiniCPM + compact)

After a Darwin switch, stop any manual `aimac-minicpm-serve` tmux so launchd owns `:8080`.
