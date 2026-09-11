# OSS private-path allowlist

This public nixos-config must not grow new **Advait-product** identifiers
(product name, crate prefix `aikya`, `setu-shell`, internal checkout/mount
paths) on files that travel GitHub.

Personal GitHub username and LAN hostnames are out of scope: they belong in a
public personal config. Live modules below are **not** renamed; they are the
known-leak inventory. Add a path here only when a hit is unavoidable in a
file that already exists.

Host check: `./apps/shared/oss-leak-fence` (also `nix run .#oss-leak-fence`
from a checkout). CI job `oss-leak-fence` in `.github/workflows/lint.yml`.

## Inventory (2026-09-11)

| Path | Why the string is there |
|------|-------------------------|
| `hosts/nixos/default.nix` | Disk label + mount `/mnt/advait-scratch` |
| `hosts/nixos/vaayu/default.nix` | Comment: `aikya` ntsync consumer |
| `modules/shared/herdr.nix` | PC worktree directory under that mount |
| `modules/shared/packages.nix` | Comment: rustc from the product flake |
| `modules/shared/zvec-grep.nix` | Index helpers for `~/work/advait{,-docs}` |
| `modules/shared/scripts/zvec-grep-post-commit.sh` | Same two roots |
| `modules/shared/grok-prompts/local-helper.md` | Product helper prompt + absolute checkouts |
| `modules/shared/grok-rules/one-grep.md` | Index tables for those checkouts |
| `modules/shared/grok-rules/zvec-grep.md` | Same |
| `AGENTS.md` | Herdr/one-grep agent docs for those paths |
| `PACKET-T-nixos-odie-config-scrub.md` | Internal packet (product mentioned) |
| `PACKET-T-nixos-onegrep-hm-build.md` | Internal packet (`ADVAIT_DOCS_ROOT`) |
| `apps/shared/oss-leak-fence` | This fence (pattern + probes) |
| `docs/oss-private-paths.md` | This allowlist |

## Allowlisted paths

```
AGENTS.md
PACKET-T-nixos-odie-config-scrub.md
PACKET-T-nixos-onegrep-hm-build.md
apps/shared/oss-leak-fence
docs/oss-private-paths.md
hosts/nixos/default.nix
hosts/nixos/vaayu/default.nix
modules/shared/grok-prompts/local-helper.md
modules/shared/grok-rules/one-grep.md
modules/shared/grok-rules/zvec-grep.md
modules/shared/herdr.nix
modules/shared/packages.nix
modules/shared/scripts/zvec-grep-post-commit.sh
modules/shared/zvec-grep.nix
```
