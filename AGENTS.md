# AI Agent Guide: Nix Configuration

This document helps AI agents understand and work with this Nix configuration repository.

## Repository Overview

This is a **Nix Flakes** configuration for both **macOS** (via nix-darwin) and **NixOS** (Linux). It uses:

- **Nix Flakes** for reproducible, declarative package management
- **Home Manager** for user-level dotfiles and programs
- **nix-darwin** for macOS system configuration
- **agenix** for secrets management

## Architecture

```
User runs: nix run .#build-switch
    │
    ▼
flake.nix (entry point)
    │
    ├── Darwin (macOS)
    │   ├── hosts/darwin/default.nix      (system config)
    │   └── modules/darwin/
    │       ├── home-manager.nix          (user config, homebrew)
    │       ├── casks.nix                 (GUI apps via Homebrew)
    │       ├── packages.nix              (darwin-specific nix packages)
    │       └── secrets.nix               (agenix secrets)
    │
    ├── NixOS (Linux)
    │   ├── hosts/nixos/default.nix       (system config)
    │   └── modules/nixos/
    │       ├── home-manager.nix          (user config, dconf/GNOME)
    │       ├── packages.nix              (nixos-specific packages)
    │       └── secrets.nix               (agenix secrets)
    │
    └── Shared (both platforms)
        └── modules/shared/
            ├── packages.nix              (CLI tools, Rust toolchain)
            ├── home-manager.nix          (shell, git, tmux config)
            ├── files.nix                 (dotfiles, SSH keys)
            ├── fonts.nix                 (font packages)
            └── default.nix               (nixpkgs config, overlays)
```

## Key Files Reference

### Entry Point

| File | Purpose |
|------|---------|
| `flake.nix` | Main entry point. Defines inputs (dependencies), outputs (configurations), and the `user` variable |

### Packages

| File | Purpose | Platform |
|------|---------|----------|
| `modules/shared/packages.nix` | CLI tools, Rust toolchain, build tools | Both |
| `modules/darwin/packages.nix` | macOS-specific nix packages | macOS |
| `modules/darwin/casks.nix` | GUI apps via Homebrew (Cursor, Ghostty, Firefox, etc.) | macOS |
| `modules/nixos/packages.nix` | NixOS GUI apps (GNOME tools, Wine, etc.) | NixOS |

### User Configuration (Home Manager)

| File | Purpose | Platform |
|------|---------|----------|
| `modules/shared/home-manager.nix` | Shell (zsh), git, tmux, environment variables | Both |
| `modules/darwin/home-manager.nix` | Dock entries, Homebrew config | macOS |
| `modules/nixos/home-manager.nix` | GNOME dconf settings | NixOS |

### System Configuration

| File | Purpose | Platform |
|------|---------|----------|
| `hosts/darwin/default.nix` | macOS system settings (keyboard, dock position, etc.) | macOS |
| `hosts/nixos/default.nix` | NixOS system config (services, networking, desktop) | NixOS |

### Files & Dotfiles

| File | Purpose |
|------|---------|
| `modules/shared/files.nix` | SSH public keys, shared dotfiles |
| `modules/darwin/files.nix` | macOS-specific dotfiles |
| `modules/nixos/files.nix` | NixOS-specific dotfiles |

## Common Tasks

### Add a CLI tool (both platforms)

Edit `modules/shared/packages.nix`:

```nix
with pkgs; [
  # existing packages...
  neovim    # add new package here
]
```

### Add a macOS GUI app

Edit `modules/darwin/casks.nix`:

```nix
[
  # existing casks...
  "discord"    # add Homebrew cask name
]
```

### Add a NixOS GUI app

Edit `modules/nixos/packages.nix`:

```nix
shared-packages ++ [
  # existing packages...
  discord    # add nixpkgs package
]
```

### Change shell aliases or environment

Edit `modules/shared/home-manager.nix`, find the `zsh.initExtra` section:

```nix
zsh = {
  initExtra = ''
    # Add aliases here
    alias ll='ls -la'
    
    # Add environment variables
    export MY_VAR="value"
  '';
};
```

### Change git config

Edit `modules/shared/home-manager.nix`, find the `git` section:

```nix
git = {
  enable = true;
  userName = "Your Name";
  userEmail = "your@email.com";
  # ...
};
```

### Modify macOS system settings

Edit `hosts/darwin/default.nix`, find the `system.defaults` section:

```nix
system.defaults = {
  dock = {
    orientation = "left";  # or "bottom", "right"
    tilesize = 48;
  };
  # ...
};
```

## Build Commands

| Command | Purpose |
|---------|---------|
| `nix run .#build` | Build without applying (test) |
| `nix run .#build-switch` | Build and apply configuration |
| `nix flake update` | Update all dependencies |

## Important Notes

### Platform Detection

Use `pkgs.stdenv.hostPlatform.isDarwin` or `pkgs.stdenv.hostPlatform.isLinux` for platform-specific code:

```nix
${lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
  # Linux-only shell config
  alias open="xdg-open"
''}
```

### GUI Apps on macOS

GUI apps with native dependencies (GTK, Wayland) should use Homebrew casks on macOS, not nixpkgs. Examples: Ghostty, Cursor, Zed.

### Secrets

Secrets are managed via agenix and stored in a private `nix-secrets` repo. Never commit private keys. Only public keys go in `modules/shared/files.nix`.

### After Making Changes

Always run:
1. `git add .` (flake requires tracked files)
2. `nix run .#build` (test build)
3. `nix run .#build-switch` (apply)

## User Configuration

Current user: `amitsheokand`
- Defined in `flake.nix` as `user = "amitsheokand"`
- Email: `amix.sheokand@gmail.com`
- Desktop: GNOME (NixOS), macOS native (Darwin)
- Focus: Rust development

## Cross-Compilation to Windows

This config includes `cargo-xwin` for cross-compiling Rust to Windows MSVC target.

### Setup

```sh
rustup target add x86_64-pc-windows-msvc
```

### Build for Windows

```sh
cargo xwin build --target x86_64-pc-windows-msvc --release
```

### Run Windows Executables

**On both macOS and NixOS:**
```sh
# Using wine directly
wine ./myapp.exe

# Using the exe alias (suppresses debug output)
exe ./myapp.exe

# Using the run-exe function
run-exe ./myapp.exe
```

**On NixOS only (binfmt enabled):**
```sh
# Run .exe files directly like native executables
./myapp.exe
```

### Wine Configuration

- `WINEDEBUG="-all"` is set by default to suppress debug noise
- Wine is installed via Homebrew on macOS and nixpkgs on NixOS
- Both use the same Wine version for consistency

### Example Project

See `~/dev/test-win32` for a sample Windows GUI app using [WinSafe](https://github.com/rodrigocfd/winsafe).
