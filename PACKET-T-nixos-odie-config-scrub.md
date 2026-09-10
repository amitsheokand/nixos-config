# Packet: T-nixos-odie-config-scrub
Auto-ID: T-nixos-odie-config-scrub
Host: nixos | Workspace: ~/dev/nixos-config (public OSS — Advait-free)
Harness: Pi → hipfire/forge (local). Soft→Zen free if forge unavailable. Never Grok implement.

## Goal
Remove **odie** as a managed host from this nixos-config after migrate close. Odie is no longer an Advait work machine.

## Do
1. Delete `hosts/nixos/odie/` (default.nix + hardware-configuration.nix).
2. Remove `nixosConfigurations.odie` (and any `odie =` system entry) from `flake.nix`.
3. Drop odie from deploy-lan / build-switch / clean host lists and aliases.
4. Remove odie from `modules/shared/ssh-host-keys.nix` knownHosts + `home-manager.nix` ssh match blocks that only exist for odie.
5. Scrub docs/`AGENTS.md` odie host sections so they no longer present odie as a live NixOS target (keep historical one-liners only if needed for LAN IP notes — prefer delete).
6. Scrub Advait-product names if any remain in touched paths (OSS Advait-free).
7. Keep nixos desktop + vaayu + darwin intact. Do **not** delete ssh *user* authorized_keys entries that are still used by other hosts unless they are odie-only dead keys.
8. `nix flake check` or at least `nix eval .#nixosConfigurations --apply builtins.attrNames` greener without `odie`.
9. Local milestone commit only; **no push** without Affirm.

## Success
- No `hosts/nixos/odie`, no flake `odie` config, deploy-lan does not list odie.
- Eval proves configs = nixos/vaayu/(garfield?) without odie.
- One-line Done/blocker for Floor.

## Out of scope
- Deleting data under /mnt/advait-scratch/odie
- Touching Advait / chromium repos
- Push to origin
- one-grep / stage0 work
