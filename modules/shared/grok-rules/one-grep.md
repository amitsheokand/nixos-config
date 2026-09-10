# one-grep (MCP `one-grep`)

Local-first hybrid search (ripgrep + BM25 + ONNX embeddings) via stdio MCP
`one-grep serve --stdio`. No daemon. Every call needs an **absolute `root`**.
The index lives under `<root>/.onegrep/`.

Tools:

- **search** — hybrid (semantic + BM25). Use for architecture, call chains,
  unknown wording, “where / how”.
- **rg** — exact text, symbol, or regex. Prefer this when the token is known.

Both take `root`. Optional `search` fields: `fts` (lexical anchors), `fuse`
(default true), `limit` (default 10).

## Indexed workspaces

Index each tree once (`one-grep index <root>` then `one-grep embed <root>`).
Do **not** index `~/work` or Advait `third_party/**`.

| Tree | Linux `root` | macOS `root` |
| --- | --- | --- |
| Nix / agents config | `/home/amitsheokand/dev/nixos-config` | `/Users/amitsheokand/dev/nixos-config` |
| hipfire | `/home/amitsheokand/dev/hipfire` | `/Users/amitsheokand/dev/hipfire` |
| Advait code | `/home/amitsheokand/work/advait` | `/Users/amitsheokand/work/advait` |
| Advait docs | `/home/amitsheokand/work/advait-docs` | `/Users/amitsheokand/work/advait-docs` |

Advait code and docs are **separate trees**. Do not search docs when the
question is about crates/tools, and vice versa.

## When to use

- **search** — architecture, call chains, cross-file “where / how”.
- **rg** (one-grep) or native grep — one exact symbol, literal, filename, or
  exhaustive match list.

Cite `path:line` evidence. Open files only when a cited range is insufficient.

## Bootstrap

```sh
# binary already on the Mac: ~/.local/bin/one-grep
one-grep index ~/work/advait
one-grep embed ~/work/advait
one-grep index ~/work/advait-docs
one-grep embed ~/work/advait-docs
```
