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
    echo "headroom: CLI not installed. It will be installed on the next home-manager activation," >&2
    echo "  or run: uv tool install --python python3 '${headroomExtras}'" >&2
    exit 127
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

  home.activation.ensureHeadroom = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="${pkgs.uv}/bin:${pkgs.python313}/bin:$HOME/.local/bin:$PATH"
    export LD_LIBRARY_PATH="${libPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    if [[ ! -x ${uvHeadroom} ]]; then
      echo "headroom: installing ${headroomExtras} via uv tool…"
      $DRY_RUN_CMD ${pkgs.uv}/bin/uv tool install --force \
        --python ${pkgs.python313}/bin/python3 \
        "${headroomExtras}"
    fi

    # Replace the uv PATH *symlink* with a NixOS-safe wrapper file.
    # Never write through the symlink — that overwrites the uv tool binary.
    if [[ -x ${uvHeadroom} ]]; then
      $DRY_RUN_CMD mkdir -p "$HOME/.local/bin"
      $DRY_RUN_CMD rm -f ${shimHeadroom}
      $DRY_RUN_CMD cp -f ${headroomWrapped}/bin/headroom ${shimHeadroom}
      $DRY_RUN_CMD chmod +x ${shimHeadroom}
      $DRY_RUN_CMD ${shimHeadroom} mcp install --force || true
    fi
  '';
} // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  # Claude Code + Codex are routed to http://127.0.0.1:8787 by `headroom init`.
  systemd.user.services.headroom-proxy = {
    Unit = {
      Description = "Headroom LLM context compression proxy";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = "${headroomWrapped}/bin/headroom proxy --host 127.0.0.1 --port 8787";
      Restart = "on-failure";
      RestartSec = "3";
      Environment = [
        "HEADROOM_TELEMETRY=off"
        "PATH=${homeDir}/.local/bin:${pkgs.uv}/bin:${pkgs.python313}/bin:/run/current-system/sw/bin"
      ];
    };
    Install.WantedBy = [ "default.target" ];
  };
}
