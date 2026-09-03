# zvec-grep (`zg`) — local-first hybrid search (ripgrep + BM25 + vectors).
# npm: @zvec/zvec-grep → ~/.local. Not in nixpkgs.
# MCP for Cursor is declared in headroom.nix (single writer of ~/.cursor/mcp.json).
# OpenCode is configured on activation via `zg install`.
# Pi / Hermes / Grok / Muse / Zed are merged by zvec-grep-merge-clients.py
# (`zg install` has no targets for those).
# Server: user systemd / Darwin launchd (`zg server run` on 127.0.0.1:7999).
#
# Index per workspace. Advait is two roots (see zg-index-advait / zg-refresh-advait).
# Incremental refresh: login (systemd/launchd) + post-commit in advait/advait-docs.
#
# Embedding: Jina code (deeper than Potion). Linux → Vulkan on the **iGPU**
# (odie Intel, vaayu Asahi, nixos desktop integrated). hipfire stays on the
# headless Radeon AI PRO R9700 (ROCm). macOS → Metal (MLX lanes for Pi/Grok).
# After switching models: ZG_REBUILD=1 zg-index-advait
{ pkgs, lib, ... }:

let
  user = "amitsheokand";
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  homeDir = if isDarwin
    then "/Users/${user}"
    else "/home/${user}";
  nodejs = pkgs.nodejs_22;
  python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  util-linux = pkgs.util-linux;
  npm = "${nodejs}/bin/npm";
  pkg = "@zvec/zvec-grep@0.2.1";
  zgBin = "${homeDir}/.local/bin/zg";
  codeRoot = "${homeDir}/work/advait";
  docsRoot = "${homeDir}/work/advait-docs";
  refreshLock = "${homeDir}/.cache/zvec-grep-refresh.lock";
  refreshLog = "${homeDir}/.cache/zvec-grep-refresh.log";
  embedModel = "local/jina-embeddings-v2-base-code";
  embedDevice = if isDarwin then "metal" else "vulkan";
  embedEnv = ''
    embed="''${ZG_EMBEDDING:-${embedModel}}"
    device="''${ZG_DEVICE:-${embedDevice}}"
    rebuild_flag=""
    if [[ "''${ZG_REBUILD:-0}" == 1 ]]; then
      rebuild_flag=--rebuild
    fi
    # zg Vulkan must stay on the iGPU. Do not inherit hipfire ROCm env (R9700).
    unset HIP_VISIBLE_DEVICES ROCR_VISIBLE_DEVICES HIP_PATH 2>/dev/null || true
  '';
  zgServicePath = lib.makeBinPath [
    pkgs.bash
    pkgs.coreutils
    util-linux
    nodejs
  ] + ":${homeDir}/.local/bin";
  zgServiceEnv = [
    "PATH=${zgServicePath}"
    "HOME=${homeDir}"
    "ZVEC_GREP_EMBEDDING=${embedModel}"
    "ZVEC_GREP_DEVICE=${embedDevice}"
  ];
  indexAdvait = pkgs.writeShellApplication {
    name = "zg-index-advait";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -euo pipefail
      zg="''${ZG:-$HOME/.local/bin/zg}"
      code="''${ADVAIT:-$HOME/work/advait}"
      docs="''${ADVAIT_DOCS:-$HOME/work/advait-docs}"
      ${embedEnv}
      if [[ ! -x "$zg" ]]; then
        echo "zg-index-advait: zg not found at $zg" >&2
        exit 1
      fi
      indexed=0
      if [[ -d "$code" ]]; then
        echo "zg-index-advait: $code ($embed on $device, exclude third_party)"
        "$zg" index "$code" --mode direct --embedding "$embed" --device "$device" \
          $rebuild_flag -g '!third_party/**'
        indexed=1
      else
        echo "zg-index-advait: skip missing $code" >&2
      fi
      if [[ -d "$docs" ]]; then
        echo "zg-index-advait: $docs ($embed on $device)"
        "$zg" index "$docs" --mode direct --embedding "$embed" --device "$device" \
          $rebuild_flag
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
  indexHipfire = pkgs.writeShellApplication {
    name = "zg-index-hipfire";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -euo pipefail
      zg="''${ZG:-$HOME/.local/bin/zg}"
      root="''${HIPFIRE:-$HOME/dev/hipfire}"
      ${embedEnv}
      if [[ ! -x "$zg" ]]; then
        echo "zg-index-hipfire: zg not found at $zg" >&2
        exit 1
      fi
      if [[ ! -d "$root" ]]; then
        echo "zg-index-hipfire: missing $root" >&2
        exit 1
      fi
      echo "zg-index-hipfire: $root ($embed on $device)"
      exec "$zg" index "$root" --mode direct --embedding "$embed" --device "$device" \
        $rebuild_flag \
        -g '!target/**' -g '!**/*.gguf' -g '!**/*.safetensors'
    '';
  };
  refreshAdvait = pkgs.writeShellApplication {
    name = "zg-refresh-advait";
    runtimeInputs = [ pkgs.coreutils util-linux ];
    text = ''
      set -euo pipefail
      zg="''${ZG:-$HOME/.local/bin/zg}"
      code="''${ADVAIT:-${codeRoot}}"
      docs="''${ADVAIT_DOCS:-${docsRoot}}"
      ${embedEnv}
      lock="''${ZG_REFRESH_LOCK:-${refreshLock}}"
      log="''${ZG_REFRESH_LOG:-${refreshLog}}"
      background=0
      scope=all
      repo_root=""

      usage() {
        echo "usage: zg-refresh-advait [--background] [--code|--docs|--repo <path>]" >&2
      }

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --background|-b) background=1; shift ;;
          --code) scope=code; shift ;;
          --docs) scope=docs; shift ;;
          --repo) scope=repo; repo_root="$2"; shift 2 ;;
          -h|--help) usage; exit 0 ;;
          *) echo "zg-refresh-advait: unknown option: $1" >&2; usage; exit 2 ;;
        esac
      done

      if [[ ! -x "$zg" ]]; then
        echo "zg-refresh-advait: zg not found at $zg" >&2
        exit 1
      fi

      refresh_root() {
        local root="$1"
        shift
        [[ -d "$root" ]] || return 0
        if [[ ! -d "$root/.zvec-grep" ]]; then
          echo "zg-refresh-advait: bootstrap $root ($embed on $device)"
          if [[ $# -gt 0 ]]; then
            "$zg" index "$root" --mode direct --embedding "$embed" --device "$device" \
              $rebuild_flag "$@"
          else
            "$zg" index "$root" --mode direct --embedding "$embed" --device "$device" \
              $rebuild_flag
          fi
        else
          if [[ $# -gt 0 ]]; then
            "$zg" index "$root" --mode direct --device "$device" "$@"
          else
            "$zg" index "$root" --mode direct --device "$device"
          fi
        fi
      }

      run_refresh() {
        mkdir -p "$(dirname "$lock")" "$(dirname "$log")"
        (
          flock -n 9 || {
            echo "zg-refresh-advait: skip (refresh already running)" >&2
            exit 0
          }
          case "$scope" in
            all)
              refresh_root "$code" -g '!third_party/**'
              refresh_root "$docs"
              ;;
            code) refresh_root "$code" -g '!third_party/**' ;;
            docs) refresh_root "$docs" ;;
            repo)
              case "$repo_root" in
                "$code") refresh_root "$code" -g '!third_party/**' ;;
                "$docs") refresh_root "$docs" ;;
                *)
                  echo "zg-refresh-advait: skip unknown repo $repo_root" >&2
                  exit 0
                  ;;
              esac
              ;;
            *)
              echo "zg-refresh-advait: invalid scope $scope" >&2
              exit 2
              ;;
          esac
        ) 9>"$lock"
      }

      if [[ "$background" -eq 1 ]]; then
        mkdir -p "$(dirname "$log")"
        reexec=( )
        case "$scope" in
          code) reexec+=(--code) ;;
          docs) reexec+=(--docs) ;;
          repo) reexec+=(--repo "$repo_root") ;;
        esac
        nohup "$0" "''${reexec[@]}" >>"$log" 2>&1 &
        exit 0
      fi

      run_refresh
    '';
  };
  postCommitHook = pkgs.writeShellApplication {
    name = "zvec-grep-post-commit";
    runtimeInputs = [ refreshAdvait pkgs.coreutils ];
    text = builtins.readFile ./scripts/zvec-grep-post-commit.sh;
  };
in
{
  home.packages = [ nodejs indexAdvait indexHipfire refreshAdvait postCommitHook ];

  home.file = {
    ".grok/rules/zvec-grep.md".source = ./grok-rules/zvec-grep.md;
    ".grok/prompts/local-helper.md".source = ./grok-prompts/local-helper.md;
  };

  home.sessionPath = [ "$HOME/.local/bin" ];

  home.sessionVariables = {
    ZVEC_GREP_EMBEDDING = embedModel;
    ZVEC_GREP_DEVICE = embedDevice;
  };

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

  home.activation.zvecGrepGitHooks = lib.hm.dag.entryAfter [ "installZvecGrep" ] ''
    install_hook() {
      local repo="$1"
      local hook="$repo/.git/hooks/post-commit"
      local ours="${lib.getExe postCommitHook}"
      [[ -d "$repo/.git" ]] || return 0
      mkdir -p "$(dirname "$hook")"
      if [[ -L "$hook" ]] && [[ "$(readlink "$hook")" == "$ours" ]]; then
        return 0
      fi
      if [[ -e "$hook" ]] && ! grep -q 'zvec-grep-post-commit' "$hook" 2>/dev/null; then
        cp -a "$hook" "$(dirname "$hook")/post-commit.local"
        chmod +x "$(dirname "$hook")/post-commit.local" 2>/dev/null || true
      fi
      ln -sfn "$ours" "$hook"
    }
    install_hook ${lib.escapeShellArg codeRoot}
    install_hook ${lib.escapeShellArg docsRoot}
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
        Environment = zgServiceEnv;
      };
      Install.WantedBy = [ "default.target" ];
    };
    zvec-grep-refresh = {
      Unit = {
        Description = "Incremental zvec-grep index (Advait workspaces)";
        After = [ "zvec-grep.service" ];
        Wants = [ "zvec-grep.service" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${lib.getExe refreshAdvait} --background";
        Environment = zgServiceEnv;
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
        PATH = zgServicePath;
        HOME = homeDir;
        ZVEC_GREP_EMBEDDING = embedModel;
        ZVEC_GREP_DEVICE = embedDevice;
      };
    };
  };

  launchdAgents.zvec-grep-refresh = {
    command = "${lib.getExe refreshAdvait} --background";
    serviceConfig = {
      RunAtLoad = true;
      StandardOutPath = "/tmp/zvec-grep-refresh_${user}.out.log";
      StandardErrorPath = "/tmp/zvec-grep-refresh_${user}.err.log";
      EnvironmentVariables = {
        PATH = zgServicePath;
        HOME = homeDir;
        ZVEC_GREP_EMBEDDING = embedModel;
        ZVEC_GREP_DEVICE = embedDevice;
      };
    };
  };
}
