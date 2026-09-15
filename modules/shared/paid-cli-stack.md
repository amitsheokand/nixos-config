Fusion / EPR / obs-pack are `--kind pi` only. This seat does not have them.
A full `cargo test` dump in chat is how the 256k window burns cache-read tokens.

## Search (one-grep)

Call MCP `search` / `rg` with **absolute** `root`:

- This worktree: `$PWD` when it is under `~/work/worktrees/…`
- Never `~/work` as one tree
- Never a primary checkout as `root` while you are in a packet tree

## After an edit (then_run equivalent)

Same turn, **one** shell, then stop:

- `cargo test -p <crate> --lib`
- `cargo xwin test -p <crate> --lib` when the packet is Windows/xwin

Quote the last ~20 lines of a failure. Do not start a second turn to “explore
the log” if a regex scout of those lines would have been enough.

## Dumps (Headroom)

`headroom_compress` before a large tool result re-enters context.
`headroom_retrieve` if you need a slice later. Do not paste the archive.

## Seat

You must be a linked git worktree (`.git` is a **file**). If `.git/` is a
**directory**, you are on a primary — stop and say so. Coordinator starts
`--kind cursor` / `--kind muse` in the worktree pane, never on a primary.
