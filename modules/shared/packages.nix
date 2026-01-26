{ pkgs, ... }:
let
  myFonts = import ./fonts.nix { inherit pkgs; };
in
with pkgs; [
  # === Rust Development ===
  rustup              # Rust toolchain installer (includes rustc, cargo, rustfmt, clippy, rust-analyzer)
  cargo-watch         # Watch for changes and run cargo commands
  cargo-edit          # Cargo subcommands: add, rm, upgrade
  cargo-nextest       # Faster test runner
  cargo-expand        # Expand macros
  cargo-audit         # Audit dependencies for security vulnerabilities
  cargo-outdated      # Check for outdated dependencies
  cargo-flamegraph    # CPU profiling flamegraphs
  cargo-deny          # Lint dependencies
  cargo-xwin          # Cross compile to Windows MSVC target
  sccache             # Shared compilation cache

  # === Core CLI Tools ===
  age                 # File encryption tool
  age-plugin-yubikey  # YubiKey plugin for age encryption
  bat                 # Cat clone with syntax highlighting
  btop                # System monitor and process viewer
  coreutils           # Basic file/text/shell utilities
  curl                # URL transfer tool
  direnv              # Environment variable management per directory
  difftastic          # Structural diff tool
  dust                # Disk usage analyzer
  fd                  # Fast find alternative
  fzf                 # Fuzzy finder
  gh                  # GitHub CLI
  git                 # Version control
  gnupg               # GNU Privacy Guard
  htop                # Interactive process viewer
  jq                  # JSON processor
  killall             # Kill processes by name
  openssh             # SSH client and server
  ripgrep             # Fast text search tool
  tmux                # Terminal multiplexer
  tree                # Directory tree viewer
  unzip               # ZIP archive extractor
  wget                # File downloader
  zip                 # ZIP archive creator
  zsh-powerlevel10k   # Zsh theme

  # === Development Tools ===
  # NOTE: GUI apps like ghostty, cursor, zed are installed via Homebrew on macOS
  # and via nixpkgs on NixOS (see platform-specific packages)
  sqlite              # SQL database engine
  lldb                # Debugger (useful for Rust)

  # === Build Tools ===
  cmake               # Cross-platform build system
  pkg-config          # Helper tool for compiling
  openssl             # TLS/SSL library (needed by many Rust crates)
] ++ myFonts
