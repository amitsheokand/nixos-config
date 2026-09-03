# zvec-grep (MCP `zvec_grep`)

Local hybrid search (ripgrep + BM25 + vectors) via MCP `zvec_grep_search` on
`http://127.0.0.1:7999/mcp` (`zvec-grep` user service). Every call needs an
**absolute `root`** for the workspace index under `<root>/.zvec-grep/`.

Embedding: **`local/jina-embeddings-v2-base-code`** (768-d, 8k-token chunks).
Linux: **Vulkan on the iGPU** (not the headless R9700 XT — that is hipfire only).
Mac: **Metal** (MLX for Pi compact / Gemma chat).

## Indexed workspaces

| Tree | Linux `root` | macOS `root` |
| --- | --- | --- |
| Nix / agents config | `/home/amitsheokand/dev/nixos-config` | `/Users/amitsheokand/dev/nixos-config` |
| hipfire | `/home/amitsheokand/dev/hipfire` | `/Users/amitsheokand/dev/hipfire` |
| Advait code | `/home/amitsheokand/work/advait` | `/Users/amitsheokand/work/advait` |
| Advait docs | `/home/amitsheokand/work/advait-docs` | `/Users/amitsheokand/work/advait-docs` |

Advait code and docs are **separate indexes**. Do not search docs when the
question is about crates/tools, and vice versa. Never index `~/work` or
`third_party/**`.

## When to use

- **zvec_grep_search** — architecture, call chains, cross-file “where / how”,
  unknown wording, design rationale.
- **grep / rg** — one exact symbol, literal, filename, or exhaustive match list.

Results include snippets; open files only when a cited range is insufficient.
Server mode refreshes in the background — use `served_from_current_index` hits
when good enough.

## Re-index after large changes

```sh
zg-refresh-advait                 # incremental (login + post-commit too)
ZG_REBUILD=1 zg-index-advait      # full rebuild both Advait roots
ZG_REBUILD=1 zg-index-hipfire     # full rebuild hipfire
```
