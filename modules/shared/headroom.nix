# Headroom — context compression for coding agents (Claude, Codex, Cursor, …).
# Installs the CLI via `uv tool`, wraps it for NixOS native libs, registers MCP,
# and (on Linux) runs the proxy as a user systemd service so Claude/Codex
# ANTHROPIC_BASE_URL / provider routing work.
#
# Extras: [proxy,mcp,code] — skip [memory] (pulls torch/CUDA).
#
# Also enable `programs.nix-ld` (modules/nixos/common.nix) for other uv wheels.
{ pkgs, lib, ... }:

let
  user = "amitsheokand";
  homeDir = if pkgs.stdenv.hostPlatform.isDarwin
    then "/Users/${user}"
    else "/home/${user}";
  headroomExtras = "headroom-ai[proxy,mcp,code]";
  uvHeadroom = "${homeDir}/.local/share/uv/tools/headroom-ai/bin/headroom";
  uvToolBinDir = "${homeDir}/.local/share/uv/tool-bin";
  shimHeadroom = "${homeDir}/.local/bin/headroom";
  libPath = lib.makeLibraryPath [
    pkgs.stdenv.cc.cc
    pkgs.zlib
    pkgs.openssl
    pkgs.curl
    pkgs.icu
  ];

  # Profile-visible wrapper (also used by the systemd unit).
  headroomWrapped = pkgs.writeShellScriptBin "headroom" ''
    export LD_LIBRARY_PATH="${libPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    if [[ -x "${uvHeadroom}" ]]; then
      exec "${uvHeadroom}" "$@"
    fi
    echo "headroom: CLI not installed. Start headroom-install.service to install it," >&2
    echo "  or run: systemctl --user start headroom-install.service" >&2
    exit 127
  '';

  installHeadroom = pkgs.writeShellScript "install-headroom" ''
    set -euo pipefail

    export HOME="${homeDir}"
    export PATH="${pkgs.uv}/bin:${pkgs.python313}/bin:${homeDir}/.local/bin:/run/current-system/sw/bin:$PATH"
    export LD_LIBRARY_PATH="${libPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export UV_TOOL_DIR="${homeDir}/.local/share/uv/tools"
    export UV_TOOL_BIN_DIR="${uvToolBinDir}"
    export UV_PYTHON_DOWNLOADS=never

    mkdir -p "$UV_TOOL_BIN_DIR"

    if [[ ! -x "${uvHeadroom}" ]]; then
      echo "headroom: installing ${headroomExtras} via uv tool"
      ${pkgs.uv}/bin/uv tool install --force \
        --python ${pkgs.python313}/bin/python3 \
        "${headroomExtras}"
    fi

    if [[ -x "${uvHeadroom}" ]]; then
      ${headroomWrapped}/bin/headroom mcp install --force || true
    fi
  '';

  cursorMcp = {
    mcpServers = {
      headroom = {
        type = "stdio";
        command = shimHeadroom;
        args = [ "mcp" "serve" "--proxy-url" "http://127.0.0.1:8787" ];
        env = {
          LD_LIBRARY_PATH = libPath;
        };
      };
    };
  };
in
{
  home.packages = [
    pkgs.uv
    pkgs.python313
    headroomWrapped
  ];

  # Global Cursor MCP (all workspaces). Project repos may also ship `.cursor/mcp.json`.
  home.file.".cursor/mcp.json" = {
    text = builtins.toJSON cursorMcp;
    force = true;
  };

  # Keep the public command path stable for Cursor/agent MCP config while uv
  # keeps the real Python environment outside ~/.local/bin.
  home.file.".local/bin/headroom" = {
    source = "${headroomWrapped}/bin/headroom";
    executable = true;
    force = true;
  };
} // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  systemd.user.services.headroom-install = {
    Unit = {
      Description = "Install Headroom CLI";
      After = [ "network.target" ];
      Wants = [ "network.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${installHeadroom}";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Claude Code + Codex are routed to http://127.0.0.1:8787 by `headroom init`.
  systemd.user.services.headroom-proxy = {
    Unit = {
      Description = "Headroom LLM context compression proxy";
      After = [ "headroom-install.service" "network.target" ];
      Wants = [ "headroom-install.service" ];
    };
    Service = {
      # token = max compression (may rewrite prior turns). code-aware needs
      # headroom-ai[code] (already in headroomExtras).
      ExecStart = "${headroomWrapped}/bin/headroom proxy --host 127.0.0.1 --port 8787 --mode token --code-aware";
      Restart = "on-failure";
      RestartSec = "3";
      Environment = [
        "HEADROOM_TELEMETRY=off"
        "HEADROOM_CODE_AWARE_ENABLED=1"
        "PATH=${homeDir}/.local/bin:${pkgs.uv}/bin:${pkgs.python313}/bin:/run/current-system/sw/bin"
      ];
    };
    Install.WantedBy = [ "default.target" ];
  };
}
