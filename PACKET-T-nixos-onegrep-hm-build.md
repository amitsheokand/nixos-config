# Packet: T-nixos-onegrep-hm-build

Role: Implementer. Follow agents/skill-usage.md + skills/packet-work when present.
Workspace primary: /home/amitsheokand/dev/nixos-config
Source tip: /home/amitsheokand/dev/one-grep @ 1f215f9 (jal onegrep-nix-hm Done GREEN)
Docs: ADVAIT_DOCS_ROOT=/home/amitsheokand/work/advait-docs

## Goal
Build / wire OSS-safe Home Manager module for one-grep into public nixos-config from jal tip `1f215f9`.

Source artifacts already mirrored on this host:
- `~/dev/one-grep/nix/home-manager/one-grep.nix`
- `~/dev/one-grep/nix/package.nix`
- `~/dev/one-grep/flake.nix` (+ lock)
- Receipt: `~/dev/one-grep/RECEIPT-T-aimac-onegrep-nix-hm.md`

Wire using existing nixos-config HM patterns (see `modules/nixos/home-manager.nix`, `modules/shared/zvec-grep.nix` style). Prefer flake input + `programs.one-grep` import over copy-paste of private paths.

Success: `nix` eval/build of the HM module / package proves green (e.g. `nix build` on one-grep package and/or `home-manager`/`nixos-rebuild` dry check as appropriate to existing repo recipes) — or cropped blocker with exact missing input.

Local milestone commit on nixos-config if real; **no push** unless Affirmed. Tip note in receipt.

## Must not
- Write Advait / private product / private hostname / private home paths into nixos-config (public OSS)
- Touch advait / crypt32 / mojo / wpf / chrome / composition residual seat
- Bare muse-spark / *-contributor*
- Push without Affirmed ask

## Routing
Mechanical. Prefer Pi → OpenCode Zen `nemotron-3.5-lightning-free` `--thinking high`. Hard → muse-code/muse-spark-1.3 only. Local tiny OK.

## Done when
HM module wired + build proof, or cropped blocker. Escalate Done/blocker one-line via Floor only.
