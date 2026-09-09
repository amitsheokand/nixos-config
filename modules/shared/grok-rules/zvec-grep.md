# zvec-grep (MCP `zvec_grep`)

Local hybrid search (ripgrep + BM25 + vectors) via MCP `zvec_grep_search` on
`http://127.0.0.1:7999/mcp` (`zvec-grep` user service). Every call needs an
**absolute `root`** for the workspace index under `<root>/.zvec-grep/`.

## Indexed workspaces

| Tree | Linux `root` | macOS `root` |
| --- | --- | --- |
| Nix / agents config | `/home/amitsheokand/dev/nixos-config` | `/Users/amitsheokand/dev/nixos-config` |
| hipfire | `/home/amitsheokand/dev/hipfire` | `/Users/amitsheokand/dev/hipfire` |
| Code workspace | `/home/amitsheokand/work/code` | `/Users/amitsheokand/work/code` |
| Docs workspace | `/home/amitsheokand/work/docs` | `/Users/amitsheokand/work/docs` |

Code and docs are **separate indexes** (override with `ZG_CODE_ROOT` /
`ZG_DOCS_ROOT`). Do not search docs when the question is about crates/tools,
and vice versa. Never index `~/work` as a whole or `third_party/**`.

## When to use

- **zvec_grep_search** — architecture, call chains, cross-file “where / how”,
  unknown wording, design rationale.
- **grep / rg** — one exact symbol, literal, filename, or exhaustive match list.

Results include snippets; open files only when a cited range is insufficient.
Server mode refreshes in the background — use `served_from_current_index` hits
when good enough.

## Re-index after large changes

```sh
zg-index-workspaces                          # code + docs roots
zg index ~/dev/hipfire -g '!target/**' ...   # hipfire
zg index <root> --embedding local/potion-code-16m-v2
```
