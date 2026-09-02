# zvec-grep (`zg`) — local-first hybrid search (ripgrep + BM25 + vectors).
# npm: @zvec/zvec-grep → ~/.local. Not in nixpkgs.
# MCP for Cursor is declared in headroom.nix (single writer of ~/.cursor/mcp.json).
# OpenCode is configured on activation via `zg install`.
# Pi / Hermes / Grok / Muse / Zed are merged by zvec-grep-merge-clients.py
# (`zg install` has no targets for those).
# Server: user systemd / Darwin launchd (`zg server run` on 127.0.0.1:7999).
#
# Index per workspace (not at activation). Advait is two roots:
#   zg-index-advait
#   # or: zg index ~/work/advait --embedding local/potion-code-16m-v2 -g '!third_party/**'
#   #      zg index ~/work/advait-docs --embedding local/potion-code-16m-v2
{ pkgs, lib, ... }:

let
  user = "amitsheokand";
  homeDir = if pkgs.stdenv.hostPlatform.isDarwin
    then "/Users/${user}"
    else "/home/${user}";
  nodejs = pkgs.nodejs_22;
  python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  npm = "${nodejs}/bin/npm";
  pkg = "@zvec/zvec-grep@0.2.1";
  zgBin = "${homeDir}/.local/bin/zg";
  indexAdvait = pkgs.writeShellApplication {
    name = "zg-index-advait";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -euo pipefail
      zg="''${ZG:-$HOME/.local/bin/zg}"
      code="''${ADVAIT:-$HOME/work/advait}"
      docs="''${ADVAIT_DOCS:-$HOME/work/advait-docs}"
      embed="''${ZG_EMBEDDING:-local/potion-code-16m-v2}"
      if [[ ! -x "$zg" ]]; then
        echo "zg-index-advait: zg not found at $zg" >&2
        exit 1
      fi
      indexed=0
      if [[ -d "$code" ]]; then
        echo "zg-index-advait: $code (exclude third_party)"
        "$zg" index "$code" --embedding "$embed" -g '!third_party/**'
        indexed=1
      else
        echo "zg-index-advait: skip missing $code" >&2
      fi
      if [[ -d "$docs" ]]; then
        echo "zg-index-advait: $docs"
        "$zg" index "$docs" --embedding "$embed"
        indexed=1
      else
        echo "zg-index-advait: skip missing $docs" >&2
      fi
      if [[ "$indexed" -eq 0 ]]; then
        echo "zg-index-advait: nothing to index" >&2
        exit 1
      fi
    '';
  };
in
{
  home.packages = [ nodejs indexAdvait ];

  home.sessionPath = [ "$HOME/.local/bin" ];

  home.activation.installZvecGrep = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="${nodejs}/bin:$PATH"
    mkdir -p "$HOME/.local"
    if [[ ! -x ${lib.escapeShellArg zgBin} ]] || \
       ! ${npm} list -g --prefix "$HOME/.local" ${pkg} >/dev/null 2>&1; then
      echo "zvec-grep: installing ${pkg} into ~/.local"
      ${npm} install -g --prefix "$HOME/.local" ${pkg} || \
        echo "zvec-grep: WARNING npm install failed (network?)" >&2
    fi
    if [[ -x ${lib.escapeShellArg zgBin} ]]; then
      export ZVEC_GREP_INSTALL_SKIP_SERVER=1
      ${lib.escapeShellArg zgBin} install --target opencode --yes || \
        echo "zvec-grep: WARNING OpenCode MCP merge failed" >&2
      ${python}/bin/python3 ${./scripts/zvec-grep-merge-clients.py} || \
        echo "zvec-grep: WARNING Pi/Hermes/Grok/Muse/Zed MCP merge failed" >&2
    fi
  '';

  systemdUserServices = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    zvec-grep = {
      Unit = {
        Description = "zvec-grep local MCP search server (:7999)";
        After = [ "network.target" ];
      };
      Service = {
        ExecStart = "${zgBin} server run";
        Restart = "on-failure";
        RestartSec = "3";
        Environment = [
          "PATH=${nodejs}/bin:${homeDir}/.local/bin"
          "HOME=${homeDir}"
        ];
      };
      Install.WantedBy = [ "default.target" ];
    };
  };

  launchdAgents.zvec-grep = {
    command = "${zgBin} server run";
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/tmp/zvec-grep_${user}.out.log";
      StandardErrorPath = "/tmp/zvec-grep_${user}.err.log";
      EnvironmentVariables = {
        PATH = "${nodejs}/bin:${homeDir}/.local/bin:/usr/bin:/bin";
        HOME = homeDir;
      };
    };
  };
}
