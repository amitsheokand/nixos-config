# Personal Nix Configuration (macOS + NixOS)

> Forked from [dustinlyons/nixos-config](https://github.com/dustinlyons/nixos-config)

## Overview

This is my personal Nix configuration for macOS (Apple Silicon) and NixOS (GNOME desktop).

It provides a reproducible, declarative development environment focused on **Rust development**.

## What's Different from Upstream

This fork has been customized with:

- **Rust-focused tooling** instead of PHP/Go/Node.js
- **GNOME desktop** instead of KDE Plasma for NixOS
- **Removed Emacs** - uses Zed/Cursor/VS Code instead
- **Cleaned up packages** - removed unused apps and overlays
- **Simplified shell config** - clean zsh setup without project-specific aliases

## Features

- **Nix Flakes**: Reproducible builds with pinned dependencies
- **Cross-Platform**: Shared config between macOS and NixOS
- **macOS Setup**: Declarative macOS with Homebrew casks, dock, and system settings
- **Managed Homebrew**: Zero maintenance via `nix-darwin` and `nix-homebrew`
- **Secrets Management**: Declarative secrets with `agenix`
- **Home Manager**: User-level configuration without extra CLI steps
- **GNOME Desktop**: Clean GNOME setup for NixOS
- **Auto-loading Overlays**: Drop a `.nix` file in `/overlays` and it runs

## Packages

### Shared (macOS + NixOS)

- **Rust**: `rustup` (includes rustc, cargo, rustfmt, clippy, rust-analyzer)
- **Cargo tools**: cargo-watch, cargo-edit, cargo-nextest, cargo-expand, cargo-audit, cargo-deny, etc.
- **CLI**: bat, btop, fd, fzf, gh, git, ripgrep, tmux, jq, difftastic, etc.
- **Build tools**: cmake, pkg-config, openssl, lldb

### macOS (Homebrew Casks)

- Cursor, Ghostty, Zed, VS Code
- Firefox, VLC, Spotify
- UTM (virtualization), BetterDisplay

### NixOS

- GNOME desktop with extensions
- Firefox, Chromium, VLC, GIMP
- Wine + Winetricks

## Quick Start

### Prerequisites

1. Install Xcode CLI tools: `xcode-select --install`
2. Install Nix: `sh <(curl -L https://nixos.org/nix/install)`
3. Enable flakes in `~/.config/nix/nix.conf`:
   ```
   experimental-features = nix-command flakes
   ```

### Build & Apply

```sh
# Build (test without applying)
nix run .#build

# Apply configuration
nix run .#build-switch
```

### Making Changes

1. Edit configuration files
2. Run `git add .`
3. Run `nix run .#build-switch`

## Layout

```
.
├── apps         # Nix commands (build, build-switch, etc.)
├── hosts        # Host-specific configuration (darwin, nixos)
├── modules      # Modular configuration
│   ├── darwin   # macOS-specific (casks, dock, system settings)
│   ├── nixos    # NixOS-specific (GNOME, packages)
│   └── shared   # Shared across platforms (packages, shell, git)
├── overlays     # Custom package overlays
└── flake.nix    # Main entry point
```

## Key Files

| File | Purpose |
|------|---------|
| `flake.nix` | Main configuration, inputs, and outputs |
| `modules/shared/packages.nix` | Shared CLI tools and Rust toolchain |
| `modules/darwin/casks.nix` | macOS GUI apps via Homebrew |
| `modules/darwin/home-manager.nix` | macOS user config and dock |
| `modules/nixos/packages.nix` | NixOS-specific packages |
| `modules/shared/home-manager.nix` | Shell config (zsh, git, tmux) |

## Secrets

This configuration uses [agenix](https://github.com/ryantm/agenix) for secrets management with a private `nix-secrets` repository.

Required SSH keys:
- `~/.ssh/id_ed25519` - GitHub access
- `~/.ssh/id_ed25519_agenix` - Secrets decryption

## Credits

Based on the excellent [dustinlyons/nixos-config](https://github.com/dustinlyons/nixos-config).

## License

MIT
