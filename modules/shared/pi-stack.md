# Pi hub — usage ladder

Pi is the coding-agent hub. It runs **inside Herdr worktree panes** on PC /
M1 / M4 (`herdr server` always on; phone/iPad uses herdr-mobile-relay or
SSH). Create/open worktrees with **Worktrunk + trunkr**
(`prefix+shift+g` / `wt switch --create`), never `git worktree add`. The
`nixos-config.pi-worktree` plugin cds the pane to the checkout and starts Pi
on `worktree.opened` as `cursor/composer-2-5:slow` (high). Cursor Ultra
(`pi-cursor-sdk`) and Muse Code Power (`pi-muse-bridge`,
`muse-code/muse-spark-1.3`) live **inside Pi**. Do not open a second control
plane for the same work.

Pipeline that must stay wired (thin harness; do not bloat the system prompt):

| Layer | Job | Where |
|-------|-----|--------|
| Herdr | panes, worktrees, idle notify | `herdr.nix` + `wt` |
| Pi | four tools + extensions | `pi-agent.nix` |
| one-grep | hybrid search, absolute `root` | MCP in Pi / Cursor / Muse / Hermes |
| Headroom | compress tool dumps before they re-enter context | MCP in Pi + Cursor; proxy `:8787` for Claude/Codex |
| Compactor | session compact at subtask boundaries | `:8091` → Mac `:8081` → iGPU `:8092` |
| Action Fusion | edit/write `then_run` (no extra model turn) | `pi-extensions/action-fusion.ts` |

Do **not** install NVIDIA SoL-Pi as a second package. It is a Pi
extension, not a harness, but three of its four mechanisms duplicate this
ladder:

| SoL-Pi | Ours | Action |
|--------|------|--------|
| Action Fusion | none before | **brought over** as `action-fusion.ts` |
| ObservationPack | Headroom MCP + FFF pages + Pi 50KB truncate | keep Headroom; exact paged recall is Headroom's job |
| Online Context Compact | `/compact` + `pi-cc-compact` + `pi-async-compaction` | do not enable OCC (it aborts the run) |
| Evidence-Preserving Reducer | overflow cheap + Headroom, later if needed | skip; would send logs to a nested model |

Grok Bot is quota-capped. [Rakazo](https://github.com/elie222/rakazo) is the
open-source persistent-bot UI (also Pi-backed). It is **not** wired here —
use Pi + this ladder until a persistent-bot UI is an explicit install.

At the start of a workday run `overflow-assign` (no `--refresh` unless the
file is missing). That writes today's free/cheap pick to
`~/.pi/agent/overflow.md`. Do not scrape
[Artificial Analysis](https://artificialanalysis.ai/models) again in the
session. Free picks are **executors** (OpenRouter, OpenCode Zen, Hermes,
Command-Code) **US-hosted only**. Reviewers are Cursor Grok and Muse in Pi.

## Pick a model (cheap first)

| Need | Where | Notes |
|------|-------|--------|
| Coordinator, boards, mechanical | Pi `cursor/composer-2-5:slow` high (Ultra) | Default. Not `:fast`. Not `longctx`. |
| Visual / XAML / capture | Pi `/model minicpm-v-4.5` + `vl-capture.py` | R9700 `:8093`. Do not paste PNGs. |
| Session compact | `/compact` → `compact/compactor` | Mac `:8081` then iGPU `:8092`. |
| Free / included cloud executor | today's `~/.pi/agent/overflow.md` | Ranked daily. Skip China-hosted and Contributor. Not a reviewer. |
| Reviewer (frozen diff) | Muse `muse-code/muse-spark-1.3` (from 14 Sep) or Grok high | Never the free overflow model. Never Contributor. |
| Bounded PE | until 14 Sep: Composer/Grok **high**; then Muse Power high | Pin Spark 1.3. Effort high, not xhigh daily. |
| Hard / novel ABI | Cursor Grok 4.6 **high**; xhigh only if labeled Hard | Conserved Ultra. |
| Parked | `longctx` MiniCPM5-2B `:8080`; hipfire 27B | Too slow / Conflicts with MiniCPM-V. |

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
