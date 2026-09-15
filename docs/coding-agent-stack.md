# Coding-agent stack (Pi + Herdr + Nix)

How a coding agent stays useful on long tasks without a second control
plane, without shipping logs to the cloud, and without stuffing every
tool dump back into the next prompt.

This is a **personal Nix home** that wires the pieces together. It is not a
product and not a fork of Pi. Live host ladder:
[`modules/shared/pi-stack.md`](../modules/shared/pi-stack.md) (installed as
`~/.pi/agent/stack.md`).

## Public repos

| Repo | What it is |
|------|------------|
| [amitsheokand/nixos-config](https://github.com/amitsheokand/nixos-config) | Nix flake (NixOS + nix-darwin). Pi extensions, compact router, MCP, overflow picker. |
| [amitsheokand/one-grep](https://github.com/amitsheokand/one-grep) | Hybrid workspace search (`one-grep` CLI + MCP `search` / `rg`). |

Upstream (not ours):

- [Pi](https://github.com/earendil-works/pi) — cheap coding-agent harness
- [Herdr](https://herdr.dev) — pane mux (`--kind pi` / `muse` / `cursor` / `hermes`)
- [Worktrunk](https://github.com/max-sixty/worktrunk) (`wt`) — git worktrees
- [Headroom](https://github.com/humanlayer/headroom) — tool-dump compression (MCP)
- [NVIDIA SoL-Pi](https://github.com/NVlabs/SoL-Pi) — four efficiency ideas; **not installed as a package**
- [Compactor](https://huggingface.co/schneewolflabs/Compactor-Qwen3.5-4B) — small local summarizer for `/compact`

## Who runs where

**Pi is the cheap hub.** Default chat is OpenCode Zen
`opencode/nemotron-3-ultra-free` (high) plus thin extensions (Fusion, EPR,
obs-pack, FFF, compact). Overflow executors are today's
`~/.pi/agent/overflow.md` (OpenRouter / Zen / Hermes Nous OSS / Command Code).
Pi does **not** wrap paid Cursor or Muse.

**Muse Code and Cursor Agent CLI are native Herdr kinds** on a **linked
worktree**:

```sh
herdr agent start NAME --kind muse --pane ID    # Muse Code CLI
herdr agent start NAME --kind cursor --pane ID  # Cursor Agent CLI
```

Never `pi-muse-bridge`. Never `pi-cursor-sdk`. Never `/model muse-code/*` or
`/model cursor/*` inside Pi. Never `--kind grok` (xAI CLI). Never those paid
kinds on a primary checkout (a directory with a `.git/` directory).

```
         Herdr pane
    ┌────────┴────────┐
    │                 │
 --kind pi      --kind muse / cursor
 Zen Nemotron     native CLI
 + extensions     (subscription)
    │
    ▼
 one-grep MCP · Headroom MCP · /compact
```

one-grep and Headroom register **as MCP on each harness**. That is search and
dump compression, not “Cursor as a provider inside Pi.”

## Why not wrap paid seats in Pi

A wrap (`pi-cursor-sdk`, `pi-muse-bridge`, `/model cursor/*`) puts a second
Node runtime and a second tool surface inside Pi. On a primary checkout that
OOM’d the machine. Paid work uses `--kind` so Cursor/Muse own their own
process.

Keep the Pi system prompt thin: four tools plus a few opt-in extensions.
Skills and search live outside the prompt.

## The ladder

| Layer | Job | Notes |
|-------|------|--------|
| Herdr | One pane, one kind | `--kind pi` (cheap) or `--kind muse` / `--kind cursor` (paid, worktree) |
| Worktrees | One task, one tree, merge deletes the tree | `wt switch --create`, never `git worktree add` |
| Pi | Cheap hub: Zen Nemotron free + extensions | Overflow, vision, `/compact`. Not a paid wrap. |
| **one-grep** | Hybrid search (`search` + `rg`) | Always pass an **absolute** `root`. Separate indexes per repo. Do not index `$HOME` as one tree. |
| Headroom | Compress tool output **before** it re-enters context | MCP on Pi / Cursor / Muse / …; HTTP proxy for Claude/Codex |
| Compact | Session compact at a **finished** subtask | Local 4B (laptop MLX) then a tiny iGPU fallback. Does **not** abort the live turn. |
| Action Fusion | `then_run` on edit/write (and `gate_*` when a packet requires a Gate) | `--kind pi` only. Native Cursor/Muse: last hunk + Gate in the same shell. |
| EPR | Shrink diagnostic logs | Regex scout first. Nested Compactor only when the scout is empty or noisy. `--kind pi` only. |
| obs-pack | Large non-log dumps | 10 KiB threshold, two full sends, then head/tail. `--kind pi` only. |

FFF (paginated grep/find) replaces Pi’s default `rg --json` dump. That is
search paging, not obs-pack.

## SoL-Pi without installing SoL-Pi

[NVIDIA SoL-Pi](https://nvlabs.github.io/SoL-Pi/) is a Pi **extension** with
four mechanisms. Installing `pi install git:github.com/NVlabs/SoL-Pi` would
duplicate compact + Headroom, abort the in-flight run (Online Context Compact),
and send cargo logs to a cloud reducer by default.

Map, don’t clone:

| SoL-Pi | Here | Why |
|--------|------|-----|
| Action Fusion | `modules/shared/pi-extensions/action-fusion.ts` | Same idea, Pi 0.85 wrappers |
| ObservationPack | Headroom (other harnesses) + `obs-pack.ts` on Pi | two full sends, then archive; recall via one-grep, not a pager |
| Online Context Compact | `/compact` + `pi-cc-compact` | **Do not enable OCC** — it compact-and-aborts, then continues |
| Evidence-Preserving Reducer | `epr.ts` | Scout, then local Compactor. No cloud reducer |

NVIDIA’s published EdgeBench numbers (fewer tokens vs stock Pi) used a
frontier model at max reasoning. We took the mechanisms that fit, not that
eval spend.

## One spawn skill

Copy-paste + verify: `~/.pi/agent/skills/herdr-pi-model-spawn/SKILL.md`.

Home Manager installs that file from
`modules/shared/herdr-pi-worktree/SKILL.md`. That Nix copy is the pin.

Do **not** `skill_manage create` / `update` `herdr-pi-model-spawn`. Hermes
memory writes a second copy under `~/.pi/agent/pi-hermes-memory/skills/` and
Pi reports `[Skill conflicts]`. Ignore the memory-dir copy. Activation
removes it. Patch the Nix file, then `home-manager switch` (or
`nix run .#build-switch`).

## Hardware (pattern, not a shopping list)

Keep **one heavy GPU client** at a time.

| Box | Job | Do not |
|-----|-----|--------|
| Discrete GPU | Local vision model (screenshots / UI) | A second llama.cpp next to it “because VRAM is free” |
| iGPU | Embeddings (one-grep ONNX) + tiny compact fallback | EPR / another 4B — it is already full |
| Laptop MLX | Compactor 4B for `/compact` and EPR | Compact on the discrete-GPU chat server |

Local 27B-class chat is parked: too slow for interactive work, and it
conflicts with the vision job.

## Privacy

- No share-by-default / contributor-style training plans.
- Cloud inference: pick the **host region**, not the brand. A US-hosted
  Qwen is fine; a first-party China catalog id is not.
- Diagnostic logs never leave the LAN. EPR fail-open (keep the original)
  rather than paraphrase.
- Secrets in a log skip reduction entirely.

## How a cheap (Pi) turn is supposed to go

1. Search with one-grep (`search` for “where / how”, `rg` for one symbol).
2. `edit` / `write` with `then_run="cargo test -p <crate> --lib"` (or the
   packet’s gate command) instead of a second bash.
3. Huge `cargo test` output → EPR receipt + `source_artifact`. Read the
   file if you need more than the quotes.
4. Other huge dumps stay full for two provider requests, then obs-pack.
   Recall with `one-grep rg ~/.pi/agent/obs/<session> -- <literal>`.
5. `/compact` when a **subtask** is done. New chat when the task is done.

Paid `--kind muse` / `--kind cursor` seats skip Fusion/EPR/obs-pack. They
still use the rest of the ladder: Headroom MCP, one-grep with **absolute
worktree `root`** (`~/work/worktrees/…`, never `~/work`), and **one shell
after edit** (`cargo test -p <crate> --lib` or `cargo xwin test`). Quote
failing lines; do not start a second “explore the log” turn. Start those
kinds in the worktree pane (`--workspace`); never on a primary checkout.

Machine files: `~/.cursor/rules/paid-cli-stack.mdc` (Agent CLI + IDE) and
`~/.config/muse/skills/paid-cli-stack/`. Confirm Agent CLI with
`agent mcp list` (`headroom: ready`, `one-grep: ready`).

## Pointers in nixos-config

| Path | Role |
|------|------|
| `modules/shared/pi-agent.nix` | Packages, settings, uninstall leftover wrap npm, spawn skill pin |
| `modules/shared/pi-extensions/` | `action-fusion.ts`, `epr.ts`, `obs-pack.ts` |
| `modules/shared/pi-compact.nix` | `:8091` router → laptop 4B, then iGPU tiny |
| `modules/shared/one-grep.nix` | MCP **on** Pi / Cursor / Muse / Hermes / … (not a Pi wrap) |
| `modules/shared/headroom.nix` | CLI + MCP + Claude/Codex proxy; Cursor Agent `mcp enable`; paid-CLI rule |
| `modules/shared/paid-cli-stack.md` | then_run-equivalent + one-grep root for Muse/Cursor |
| `modules/shared/pi-stack.md` | Live usage ladder |
| `modules/shared/herdr-pi-worktree/SKILL.md` | Only spawn skill (`herdr-pi-model-spawn`) |
| `modules/shared/scripts/then_run_uptake.py` | Count Fusion uptake in Pi session JSONL |

## What this is not

- Not `pi install` SoL-Pi.
- Not Cursor or Muse as `/model` providers inside Pi.
- Not `pi-muse-bridge` / `pi-cursor-sdk`.
- Not a second agent product on top of Pi.
- Not a prompt-search campaign to force 100% `then_run` uptake.
- Not “index the whole home directory.”
- Not compact-as-a-substitute-for-a-new-chat.

If you already run Pi, the reusable parts are **one-grep** (any harness) and
the three thin extensions under `pi-extensions/`. The rest is Nix glue so a
new machine gets the same ladder.
