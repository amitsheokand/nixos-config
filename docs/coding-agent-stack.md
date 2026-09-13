# A thin coding-agent stack (Pi + Nix)

How a coding agent can stay useful on long tasks without a second harness,
without shipping logs to the cloud, and without stuffing every tool dump
back into the next prompt.

This is a **personal Nix home** that wires the pieces together. It is not a
product and not a fork of Pi.

## Public repos

| Repo | What it is |
|------|------------|
| [amitsheokand/nixos-config](https://github.com/amitsheokand/nixos-config) | Nix flake (NixOS + nix-darwin). Pi extensions, compact router, MCP, overflow picker. |
| [amitsheokand/one-grep](https://github.com/amitsheokand/one-grep) | Hybrid workspace search (`one-grep` CLI + MCP `search` / `rg`). |

Upstream (not ours):

- [Pi](https://github.com/earendil-works/pi) — coding-agent harness
- [Worktrunk](https://github.com/max-sixty/worktrunk) (`wt`) — git worktrees
- [Headroom](https://github.com/humanlayer/headroom) — tool-dump compression (MCP)
- [NVIDIA SoL-Pi](https://github.com/NVlabs/SoL-Pi) — four efficiency ideas; **not installed as a package**
- [Compactor](https://huggingface.co/schneewolflabs/Compactor-Qwen3.5-4B) — small local summarizer for `/compact`

Herdr is the pane mux on machines that have it (one worktree, one pane). The
same stack works without it: open Pi in the worktree yourself.

## Why Pi stays the hub

One control plane. Cursor, Muse, Grok, and local OpenAI-compatible models are
**providers inside Pi**, not a second agent chatting about the same files.

Keep the system prompt thin: four tools plus a few opt-in extensions. Skills
and search live outside the prompt.

```
                    ┌──────────────────────────────┐
                    │  Pi  (edit / write / bash)     │
                    │  + then_run  + extensions      │
                    └────────┬───────────┬──────────┘
           worktrees         │           │         MCP
              wt / Herdr     │           │
                             ▼           ▼
                      one-grep          Headroom
                   search + rg      compress dumps
                   (absolute root)   (Cursor / Claude / Codex)

        large bash/read ──► obs-pack (after 2 full sends)
        cargo/test logs ──► EPR (regex scout, then local Compactor)
        /compact ──────────► compact router → laptop 4B, else iGPU tiny
```

## The ladder

| Layer | Job | Notes |
|-------|------|--------|
| Worktrees | One task, one tree, merge deletes the tree | `wt switch --create`, never `git worktree add` |
| Pi | Edit / write / bash | Default chat: a capable subscription model at **high**, not a local 2B chat model |
| **one-grep** | Hybrid search (`search` + `rg`) | Always pass an **absolute** `root`. Separate indexes per repo. Do not index `$HOME` as one tree. |
| Headroom | Compress tool output **before** it re-enters context | MCP on Cursor; HTTP proxy for Claude/Codex. Pi does not call it on every bash. |
| Compact | Session compact at a **finished** subtask | Local 4B (laptop MLX) then a tiny iGPU fallback. Does **not** abort the live turn. |
| Action Fusion | `then_run` on edit/write | Test/build/check in the same tool turn. Optional; the model has to pass it. |
| EPR | Shrink diagnostic logs | Regex scout first. Nested Compactor only when the scout is empty or noisy. Quotes must be **byte-exact** or the original log stays. Fail-open. Logs stay on the LAN. |
| obs-pack | Large non-log dumps | 10 KiB threshold, two full sends, then head/tail + a file handle. Recall with `one-grep rg` or `sed` on the archive. Not SoL-Pi’s `obs_recall` pager. |

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
| Evidence-Preserving Reducer | `epr.ts` | Scout, then local Compactor. No Luna, no overflow model, no Grok |

NVIDIA’s published EdgeBench numbers (fewer tokens vs stock Pi) used a
frontier model at max reasoning. We took the mechanisms that fit, not that
eval spend.

Their conservative profile is Fusion + ObservationPack only. That matches
what is on by default here, plus a **local** reducer instead of a paid API.

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

## How a turn is supposed to go

1. Search with one-grep (`search` for “where / how”, `rg` for one symbol).
2. `edit` / `write` with `then_run="cargo test -p <crate> --lib"` (or the
   packet’s gate command) instead of a second bash.
3. Huge `cargo test` output → EPR receipt + `source_artifact`. Read the
   file if you need more than the quotes.
4. Other huge dumps (read of a 200k file, a JSON blob) stay full for two
   provider requests, then obs-pack. Recall with
   `one-grep rg ~/.pi/agent/obs/<session> -- <literal>`.
5. `/compact` when a **subtask** is done. New chat when the task is done.
   Early compact is not a mechanism.

## Pointers in nixos-config

| Path | Role |
|------|------|
| `modules/shared/pi-agent.nix` | Packages, settings, extension install |
| `modules/shared/pi-extensions/` | `action-fusion.ts`, `epr.ts`, `obs-pack.ts` |
| `modules/shared/pi-compact.nix` | `:8091` router → laptop 4B, then iGPU tiny |
| `modules/shared/one-grep.nix` | MCP for Pi / Cursor / Muse / Hermes / … |
| `modules/shared/headroom.nix` | CLI + MCP + Claude/Codex proxy |
| `modules/shared/pi-stack.md` | Live usage ladder (host-specific) |
| `modules/shared/scripts/then_run_uptake.py` | Count Fusion uptake in Pi session JSONL |

## What this is not

- Not `pi install` SoL-Pi.
- Not a second agent product on top of Pi.
- Not a prompt-search campaign to force 100% `then_run` uptake.
- Not “index the whole home directory.”
- Not compact-as-a-substitute-for-a-new-chat.

If you already run Pi, the reusable parts are **one-grep** (any harness) and
the three thin extensions under `pi-extensions/`. The rest is Nix glue so a
new machine gets the same ladder.
