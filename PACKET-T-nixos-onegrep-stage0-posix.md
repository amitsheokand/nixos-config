# Packet: T-nixos-onegrep-stage0-posix

Role: Implementer. On-machine thin research/fix.
Workspace: /home/amitsheokand/dev/nixos-config (+ ~/dev/one-grep @ 1f215f9 for package source)
Prior: T-nixos-onegrep-hm-build Done—blocker @ a8264a1 — HM wired (enable=false); `nix build .#one-grep` blocked on missing nixpkgs bootstrap seed `stage0-posix` (`/1rz4g4…`) not in store/substituters; repo.or.cz/gnu mirrors flaky (one retry once succeeded).

## Goal
Unblock `nix build` of one-grep / stage0-posix seed using **in-repo patterns only** (existing substituters, binary caches, prefetch, known nixos-config recipes). Prefer cache/seed fix over inventing new bootstrap.

Success: `nix build` path for one-grep (or documented `pkgs.one-grep`) progresses past stage0-posix missing-seed, OR cropped blocker naming exact architecture fork / missing Affirmed input.

Local milestone if real; **no push** unless Affirmed. If true architecture fork → escalate once, stop thrash.

## Must not
- Invent new bootstrap architecture without escalate
- Push without land Affirm
- Touch docs-main-merge / composition-dxgi / odie Phase2
- Leak private paths into flake.lock (path:../one-grep rejected)
- Bare muse-spark / *-contributor*

## Routing
Bounded→Hard. Prefer Pi Zen `nemotron-3.5-lightning-free` `--thinking high`. Hard → muse-code/muse-spark-1.3 --yolo.

## Done when
stage0 unblocked or cropped arch blocker. Escalate Done/blocker one-line via Floor.
