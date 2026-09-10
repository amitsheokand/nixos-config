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
    │   ├── hosts/nixos/default.nix       (desktop PC)
    │   ├── hosts/nixos/vaayu/            (M1 Air Asahi, aarch64)
    │   └── modules/nixos/
    │       ├── home-manager.nix          (desktop GNOME)
    │       ├── home-manager-vaayu.nix    (Air: slim HM + Pi/OpenRouter)
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
| `hosts/nixos/default.nix` | Desktop PC (AMD, Sunshine) | NixOS |
| `hosts/nixos/vaayu/` | MacBook Air M1 Asahi (minimal GNOME) | NixOS aarch64 |

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
| `nix run .#deploy-lan` | `git pull` + `nixos-rebuild switch` on nixos/vaayu over SSH |
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

## Agent CLIs (base install)

Shared NixOS (`common.nix`) and Darwin ship **`pi`**, **OpenCode CLI**,
**Hermes Agent**, **Hermes Desktop**, and **Grok** (`grok` only — the
llm-agents `agent` symlink is stripped so Cursor CLI keeps `agent`) from
[`llm-agents.nix`](https://github.com/numtide/llm-agents.nix),
plus **Command Code** (`cmd` via npm → `~/.local`) and **Muse Code**
(`muse` from [`muse-code-package.nix`](modules/shared/muse-code-package.nix)).
**Cursor** comes from `pkgs.code-cursor` (NixOS) or Homebrew/nix on Darwin.
**OpenCode GUI** is separate: `pkgs.opencode-desktop` (NixOS) / cask `opencode-desktop` (Darwin).
Claude Code / Codex / prime-agent are **not** installed from `llm-agents.nix`.

| Tool | NixOS | Darwin |
|------|-------|--------|
| Pi | `agents.pi` (llm-agents.nix) | same |
| OpenCode CLI | `agents.opencode` (llm-agents.nix) | same |
| OpenCode GUI | `pkgs.opencode-desktop` | Homebrew cask `opencode-desktop` |
| Hermes Agent | `agents.hermes-agent` (`hermes`) | same |
| Hermes Desktop | `agents.hermes-desktop` | same |
| Grok | `grokCli` (`agents.grok` minus `agent`) | same |
| Muse Code | `muse-code-package.nix` (`muse`) | same |
| Command Code | HM `modules/shared/command-code.nix` | same |
| one-grep | flake input `github:amitsheokand/open-grep` (`pkgs.one-grep`) | same |
| zvec-grep (`zg`) | Linux fallback; Darwin launchd **off** | npm `@zvec/zvec-grep` |
| Cursor | `pkgs.code-cursor` | nixpkgs / cask ecosystem |

## Herdr (always-on agent mux)

[Herdr 0.9](https://herdr.dev/blog/connecting-the-machines/) is the terminal
runtime. Each of **PC (`nixos`)**, **M1 (`vaayu`)**, **M4 (`ai-mac`)** runs
`herdr server` at login. Agents keep running after detach (`ctrl+b q`). One
TUI can attach to every host over LAN SSH (`herdr machine add`).

| Piece | Where |
|-------|--------|
| Binary | `modules/shared/herdr-package.nix` (upstream **0.9.0**; nixpkgs is 0.8) |
| HM + config | `modules/shared/herdr.nix` |
| Server | user systemd `herdr-server` (NixOS) / launchd `herdr-server` (Darwin) |
| Worktrees | nixpkgs `worktrunk` (`wt`) + plugin `disintegrator/trunkr` |
| Pi in panes | plugin `nixos-config.pi-worktree` on `worktree.created`; `prefix+shift+i` |
| Idle callback | plugin `nixos-config.agent-idle` on `pane.agent_status_changed` |
| Phone / iPad | plugin `0cv/herdr-mobile-relay` PWA, or `ssh <host>` then `herdr` |

Happier is **not** the phone/iPad path. Leave the desktop AppImage bits until
Herdr has been stable; then remove Happier from every host.

```sh
herdr                  # attach Local
herdr-lan              # print PC / M1 / M4 add commands
herdr-lan apply        # herdr machine add nixos/vaayu/ai-mac (interactive)
# prefix+shift+g  create worktree (wt + trunkr)
# prefix+shift+o  open worktree
# prefix+shift+i  start Pi in the focused pane
herdr plugin action invoke setup --plugin herdr-mobile-relay.events
herdr agent wait <name> --until idle --timeout 3600000   # block this pane
# named implementer idle/done/blocked → toast + prompt idle coordinator
```

**Muse Spark** is two products with **different bills**:

| Path | Auth | Bill |
|------|------|------|
| **Muse Code** (`muse`) + browser `/login` | Meta account OAuth | **Subscription** (flat monthly). Only this CLI. |
| Pi / OpenCode / Hermes / Grok / Zed `openai_compatible` + `MODEL_API_KEY` | extra Model API key | **Pay-as-you-go per token** |

Do **not** export `META_API_KEY` / `MODEL_API_KEY` in the shell if you want the subscription. Those env vars always win over the account session. Extra keys you create in the [Model API dashboard](https://dev.meta.ai/) are PAYG; the subscription credential is attached during Muse Code account onboarding and is **Muse Code only** ([subscriptions](https://ai.developer.meta.com/docs/muse-code/subscriptions)).

Hipfire/`forge` stays the local default.

```sh
muse          # /login → Sign in with your browser (not "paste an API key")
# keep Pi on /model forge — Spark in Pi is PAYG
```

`muse-spark-proxy` (`:8082`) and `~/.config/meta.env` are **PAYG only**. Do not start the proxy or source that file unless you intend token billing. Spark reuses `tool_call_id=call_0`; the proxy exists only for that Chat Completions bug.

```sh
muse --version
grok --version
command -v agent   # must stay Cursor (~/.local/bin/agent)
```

## one-grep (agent hybrid search)

`one-grep` is the **agent** hybrid search (ripgrep + BM25 + ONNX, stdio MCP).
Source: [github.com/amitsheokand/open-grep](https://github.com/amitsheokand/open-grep)
(CLI name `one-grep`; Nix also installs an `open-grep` alias). Every host
installs the flake package via Home Manager — no cargo symlink required.

| Piece | Path |
|-------|------|
| Flake input | `open-grep` → `github:amitsheokand/open-grep` |
| HM wiring | `modules/shared/one-grep.nix` |
| Extra clients | `modules/shared/scripts/one-grep-extra-clients.py` (Grok + Zed + strip `zvec_grep`) |
| Agent rules | `modules/shared/grok-rules/one-grep.md` |

Activation upserts stdio `one-grep serve --stdio` and, because the Nix binary
is always present, **removes `zvec_grep`**. Restart the agent after switch.

Tools (absolute `root` required; index in `<root>/.onegrep/`):

| Tool | Use |
|------|-----|
| `search` | architecture, call chains, unknown wording (hybrid) |
| `rg` | exact symbol, literal, regex |

```sh
command -v one-grep
one-grep index ~/work/advait && one-grep embed ~/work/advait
one-grep index ~/work/advait-docs && one-grep embed ~/work/advait-docs
# skip third_party; do not index ~/work as one tree
```

Apply: `nix run .#build-switch` locally, `nix run .#deploy-lan` for NixOS
boxes, `nh darwin switch` on the Mac. Then **restart the agent**. First index
each workspace once; `search` falls back to BM25 if `embed` has not been run.

## zvec-grep (`zg`, leftover CLI)

npm `@zvec/zvec-grep` remains installed on Linux for the old `zg` CLI. Agent
MCP is **one-grep**. Darwin does not start launchd `zvec-grep`.

## Git clients (all hosts)

| Tool | Source | Notes |
|------|--------|--------|
| `gh` / `glab` | nixpkgs (`gh` also via HM `programs.gh`) | `gh auth login`, `glab auth login` |
| GitButler | llm-agents.nix `gitbutler` + `but` (NixOS); Homebrew cask `gitbutler` (Darwin) | nixpkgs also has `gitbutler` but older |
| rgitui | `modules/shared/rgitui-package.nix` (upstream binaries) | x86_64 Linux + Apple Silicon macOS; **no aarch64-linux release** |

## MacBook Air Asahi (`vaayu`)

| Piece | Where |
|-------|--------|
| Flake | `nixosConfigurations.vaayu` (`aarch64-linux`) |
| Host | `hosts/nixos/vaayu/` |
| HM | `modules/nixos/home-manager-vaayu.nix` |
| Asahi | `apple-silicon` flake input + `hardware.asahi.enable` |
| Apps | Minimal GNOME + Firefox + Cursor + Pi (no games/office/Wine) |

First rebuild on the Air (vendor firmware from ESP — requires impure):

```sh
mkdir -p ~/dev && cd ~/dev
git clone git@github.com:amitsheokand/nixos-config.git   # or HTTPS
cd nixos-config
sudo nixos-rebuild switch --flake .#vaayu --impure
reboot
```

Then copy `~/.config/openrouter.env` from another machine for Pi overflow
(`overflow-assign`).
On the Air, `ssh-keygen -t ed25519` and append `~/.ssh/id_ed25519.pub` to [`modules/shared/ssh-keys.nix`](modules/shared/ssh-keys.nix).

## LAN SSH + deploy

Pubkeys for Mac / desktop live in [`modules/shared/ssh-keys.nix`](modules/shared/ssh-keys.nix) (`authorized_keys` on every host). Server host keys (so this Mac can `ssh nixos` without TOFU) live in [`modules/shared/ssh-host-keys.nix`](modules/shared/ssh-host-keys.nix) → `~/.ssh/known_hosts.lan` plus NixOS `programs.ssh.knownHosts`. Aliases: `ssh nixos`, `ssh vaayu`, `ssh ai-mac`.

From Mac (after this generation is on the boxes):

```sh
nix run .#deploy-lan           # all NixOS hosts
nh os switch                   # local NixOS (after clone)
nh darwin switch               # local Mac (Determinate Nix)
```

NixOS QoL: `programs.nh` auto-cleans generations older than 7d (keep 3), systemd-boot `configurationLimit = 3` (vaayu = 2 gens, vaayu nh keep 2 / 3d), `boot.tmp.cleanOnBoot`, store `min-free` auto-GC.

## Headroom (context compression)

[Headroom](https://github.com/headroomlabs-ai/headroom) compresses tool
outputs / logs before they hit the LLM. Wired for Claude Code, Codex, and
Cursor.

| Piece | Where |
|-------|--------|
| Module | `modules/shared/headroom.nix` |
| Packages | `uv`, `python313` (+ NixOS-safe `headroom` wrapper) |
| NixOS libs | `programs.nix-ld` in `modules/nixos/common.nix` |
| Proxy | user systemd unit `headroom-proxy` (port `8787`) |
| Cursor MCP | `~/.cursor/mcp.json` (HM-managed) |
| Cursor wrap | user systemd unit `headroom-cursor-wrap` (RTK hooks + `agent mcp enable`) |

Install extras: `headroom-ai[proxy,mcp,code]` (skip `[memory]` — pulls torch).

After `nix run .#build-switch`:

```sh
headroom doctor          # proxy + agent routing health
headroom mcp status      # Claude / Codex MCP registration
systemctl --user status headroom-proxy
```

**Cursor / Agent CLI** (Grok, Composer, Auto still talk to `api2.cursor.sh`):
Headroom cannot wrap Cursor-hosted model traffic. Do **not** set
`CURSOR_API_ENDPOINT` / `--endpoint` to `:8787` — that is a different
protocol and will break Agent CLI.

What *is* wired:
- MCP tools (`headroom_compress` / retrieve) via `~/.cursor/mcp.json`
- `agent mcp enable headroom` (user systemd `headroom-cursor-wrap`)
- RTK shell hooks (`headroom wrap cursor --prepare-only`)

OpenAI **BYOK** only: Settings → Models → Override OpenAI Base URL →
`http://127.0.0.1:8787/v1`. That does not affect Grok/Composer.

**Claude / Codex** already route via `headroom init -g` (`ANTHROPIC_BASE_URL` /
Codex `model_provider = "headroom"`). They need the proxy running.

## Local helpers in Grok `/model`

Cloud `grok-*` stay in the picker. Local servers register as `[model.*]` in
`/etc/grok/managed_config.toml` (do **not** set `GROK_MODELS_BASE_URL` on the
normal `grok` session — that replaces the cloud catalog).

| Host | Grok `/model` | Pi `/model` | API `model` |
|------|---------------|-------------|-------------|
| Mac (`ai-mac`) | `longctx` (default MiniCPM5-2B `:8080`), `gemmacoder` when `mlx-lane gemma` | default `mlx-local` / `longctx`. Compactor `:8081`. `/model forge` → PC hipfire | MiniCPM aliases `longctx`/`minicpm`. Gemma path on demand. Compact `compactor`. hipfire `http://nixos.local:8080/v1` |
| PC (`nixos`) | `forge` (Grok default), `anvil`, `feather`, `qwen38` | default **`longctx`** (Mac MiniCPM over LAN). `/model forge` for Qwen 3.8 | longctx at `http://ai-mac.local:8080/v1`; lanes at `http://127.0.0.1:8080/v1` (proxy → hipfire `:11435`). Catalog: `modules/shared/agent-profiles.nix` |
| Air (`vaayu`) | `forge` (LAN) | default `longctx` (Mac); `/model forge` desktop catalog; cloud overflow via `~/.pi/agent/overflow.md` | same ids |

PC local profiles (names stay if the checkpoint changes):

| Profile | Cursor analogue | Thinking | Effort | Use |
|---------|-----------------|----------|--------|-----|
| `feather` | — | on (low, 512-token cap) | greedy; **DFlash on Qwen 3.8** | short/fast, **32k** window, 8k gen |
| `forge` | Composer | on (medium, 4096-token cap; old think stripped) | greedy AR | **daily on Qwen 3.8 mq4-pro**, 48k window, Pi auto-compacts |
| `anvil` | Grok | on (xhigh, 8192-token cap; old think stripped) | xhigh | **hard long-form on Qwen 3.8**, same 48k compact window |
| `qwen38` | — | raw backend | none injected | explicit Qwen 3.8 weight |
| `fuse` | — | lane, thinking off | none injected | Fuse-2 MoE k=2 (native template). `fuse-2-moe` is the raw backend id; `forge/fuse` is unsupported (forge thinking breaks it) |

Long sessions stay on **Qwen 3.8 mq4-pro** (`forge` / `anvil` / `feather`). Advertised windows stay 32k (feather) / 48k (forge/anvil). hipfire `memory.max_seq=65536` is the product fail-closed ceiling. An isolated 86k/98k probe is a temp project, not a catalog size. Pi compaction (`pi-async-compaction` + `compaction.enabled`) fires from ~60% of the advertised window.

Default `AI_MODEL` / `GROK_LOCAL_MODEL` on the **PC** is the hipfire **lane** `forge`, never a checkpoint name. **Pi** defaults to `longctx` (MiniCPM on the Mac) so opening `pi` does not steal the GPU. `/model fuse` swaps the desktop GPU to Fuse-2 MoE (no thinking); `/model forge` stays Qwen.

Do not enable hipfire's NixOS module here: it rebuilds the crate and overwrites `~/.hipfire/config.toml`. The desktop uses `modules/shared/hipfire-local.nix` (existing cargo binaries + user config). After `build-switch`: `systemctl --user start hipfire-serve hipfire-profile-proxy hipfire-daemon-watch` (WantedBy default.target). Serve binds **127.0.0.1:11435**; LAN clients use the catalog at `:8080` (clamp `max_tokens`, inject think caps, HTTP 413 on oversize). hipfire itself refuses to bump `memory.max_seq`. The watch unit restarts serve if `/health` is up but `daemon.pid` is dead or zombie (the 2026-08-28 failure mode). Hermes gets `/model forge`, `/model anvil`, `/model feather`, plus backend aliases; the Nous default provider is unchanged. Cursor Agent stays on cloud Grok/Composer; Continue / `cursor-local-help` use the named profiles. Zed gets `language_models.openai_compatible.hipfire` without changing `agent.default_model`.

### Shared Pi agent (Mac / PC / vaayu)

Pi is the hub. It runs inside **Herdr worktree panes** (always-on `herdr
server` on PC / M1 / M4). Cursor (`pi-cursor-sdk`) and Muse Code Power (`pi-muse-bridge`,
pin `muse-code/muse-spark-1.3`) run **inside Pi**. Usage ladder:
`modules/shared/pi-stack.md` → `~/.pi/agent/stack.md`. Grok Bot is not the
coordinator seat. Rakazo is not packaged.

| Piece | Where |
|-------|--------|
| Packages + UI | `modules/shared/pi-agent.nix` (cursor-sdk, muse-bridge 0.3.0, tool-display, statusline, pi-fff, pi-cc-compact, …) |
| Compact model | Mac MLX Compactor on `:8081` (login). Fits with MiniCPM `:8080`. `mlx-lane gemma` is exclusive (stops both). PC router `:8091` → Mac `:8081`, then local tiny. `PI_CC_COMPACT_MODEL`. Never hipfire. |
| Local model defaults | MiniCPM `longctx` (Mac `:8080`, LAN on PC/vaayu). `/model forge` for Qwen 3.8. Gemma on demand. |
| Auth keys | machine-local `~/.pi/agent/auth.json` (not in git) |

After `nix run .#build-switch` on each machine, missing `pi install` packages are pulled automatically. On a new host, still run `pi` → `/login` once for Cursor SDK / Codex keys. Pi compaction is on by default (`compaction.reserveTokens=4096`, `keepRecentTokens=12000`, `PI_ASYNC_PREFIX_COMPACTION_START_RATIO=0.6`). Manual `/compact` uses **pi-cc-compact**. Mac talks to Compactor on `:8081` (`mlx-compact/compactor`, thinking off, 16k). The GPU host uses `compact/compactor` via `:8091` (Mac `:8081`, then local 0.8B on iGPU). `PI_ASYNC_PREFIX_COMPACTION=0` on the GPU host so background compact does not share Anvil's hipfire queue. Do not compact on Anvil/hipfire.

**Session knowledge (do not stuff the prompt):**
- hermes-memory is **policy-only** (`modules/shared/pi-hermes-memory-config.json`). Never `legacy-inject`. Recall with `memory_*` tools; compact flushes via `compact/compactor` so it does not steal the R9700 slot.
- Rewind with `/tree`, do not resume a long leaf. New chat per task.
- `/compact` before huge tool dumps. Quote last 20 log lines, not the file.
- Standing pins: `modules/shared/pi-standing.md` → `~/.pi/agent/pi-hermes-memory/STANDING.md` (installed only if missing, so `/memory-pin` wins after that). Ladder: `~/.pi/agent/stack.md` (always refreshed). Cloud **executor**: `overflow-assign` → `~/.pi/agent/overflow.md` (OpenRouter / Zen / Hermes / `cmd`; do not re-rank mid-day; reviewers are Muse + Cursor Grok in Pi).
- One GPU client at a time. Headroom in front of `:8080` is optional later, not on this path.

Pi `id` is sent to the server. mlx-lm treats unknown ids as a new checkpoint and can crash. MiniCPM aliases `longctx` / `minicpm` on `:8080`. Do **not** send `gemmacoder` to MiniCPM. Gemma still uses the filesystem path when `mlx-lane gemma` owns `:8080`. `/model forge` on Mac/vaayu uses the desktop catalog at `http://nixos.local:8080/v1`. On the PC, hipfire ids are lane names (`forge` / `anvil` / `feather`); the proxy rewrites them to the hipfire tag.

`agent` on PATH is Cursor CLI (`~/.local/bin/agent`). Grok TUI is `grok` only
(the grok package `agent` alias is stripped).

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
