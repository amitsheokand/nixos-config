# Pi hub — usage ladder

Pi is the coding-agent hub. It runs **inside Herdr worktree panes** on PC /
M1 / M4 (`herdr server` always on; phone/iPad uses herdr-mobile-relay or
SSH, not Happier). Create/open worktrees with **Worktrunk + trunkr**
(`prefix+shift+g` / `wt switch --create`), never `git worktree add`. The
`nixos-config.pi-worktree` plugin cds the pane to the checkout and starts Pi
on `worktree.opened`. Cursor (Ultra, via `pi-cursor-sdk`) and Muse
Code Power (via `pi-muse-bridge`, `muse-code/muse-spark-1.3`) live **inside
Pi**. Do not open a second control plane for the same work.

Grok Bot is quota-capped. [Rakazo](https://github.com/elie222/rakazo) is the
open-source persistent-bot UI (also Pi-backed). It is **not** wired here —
use Pi + this ladder until a persistent-bot UI is an explicit install.

At the start of a workday run `overflow-assign` (no `--refresh` unless the
file is missing). That writes today's free/cheap pick to
`~/.pi/agent/overflow.md`. Do not scrape
[Artificial Analysis](https://artificialanalysis.ai/models) again in the
session. Free picks are **executors** (OpenRouter, OpenCode Zen, Hermes,
Command-Code). Reviewers are Cursor Grok and Muse in Pi.

## Pick a model (cheap first)

| Need | Where | Notes |
|------|-------|--------|
| Herding, boards, mechanical, long logs | Pi `longctx` (MiniCPM5-2B on Mac `:8080`, 64k) | Default. Does not occupy the desktop GPU. |
| Local quality / long session | Pi `forge` then `anvil` (Qwen 3.8 on the PC) | One GPU client at a time. |
| Short local | Pi `feather` | Same Qwen weights, DFlash. |
| Free / included cloud executor | today's `~/.pi/agent/overflow.md` | Ranked daily from AA × OpenRouter / Zen / Hermes / `cmd`. Use any listed harness. Not a reviewer. Not a pinned id. Not for confidential packets. |
| Reviewer (frozen diff) | Pi Muse `muse-code/muse-spark-1.3` or Cursor Grok / Composer (`pi-cursor-sdk`) | Do **not** review with the free overflow model. |
| Bounded/Hard PE implementer | `muse-code/muse-spark-1.3` or `subagent({ agent: "muse-spark" })` | Muse **Code Power** / `muse login`. Never `*-contributor*`. Never `MODEL_API_KEY`. |
| Scarce IDE / hard twin | `cursor/composer-2-5` (SDK key) or Cursor Ultra in the IDE | Two different pools. Conserve both. |

## Privacy

- No China-hosted cloud endpoints.
- No share-by-default / Contributor plans.
- Local weights on our machines are fine (any origin).
- GLM / Qwen / DeepSeek cloud OK only when the **host** is outside China.

## Mac MLX lanes (`mlx-lane`)

- `minicpm` / `longctx` — default `:8080`, can share RAM with compact `:8081`
- `compact` — `:8081` Compactor 4B (Pi `/compact` only)
- `gemma` — 12B coder, exclusive (stops MiniCPM + compact)

After a Darwin switch, stop any manual `aimac-minicpm-serve` tmux so launchd owns `:8080`.
