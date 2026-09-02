# Desktop compact sidecar: Mac Compactor primary, local tiny fallback.
# Listens on 127.0.0.1:8091. Never hipfire :11435 or catalog :8080.
{
  pkgs,
  lib,
  user,
}:

let
  homeDir = "/home/${user}";
  python = pkgs.python3;
  focusFile = ./pi-compact/focus.md;
  routerSrc = ./pi-compact/compact-router.py;
  skillSrc = ./pi-compact/SKILL.md;
  tinySrc = ./pi-compact/tiny-server.sh;

  router = pkgs.writeShellApplication {
    name = "pi-compact-router";
    runtimeInputs = [ python ];
    text = ''
      export COMPACT_FOCUS_FILE=${lib.escapeShellArg "${focusFile}"}
      export COMPACT_LISTEN_HOST="''${COMPACT_LISTEN_HOST:-127.0.0.1}"
      export COMPACT_LISTEN_PORT="''${COMPACT_LISTEN_PORT:-8091}"
      export COMPACT_PRIMARY_BASE="''${COMPACT_PRIMARY_BASE:-http://ai-mac.local:8081/v1}"
      export COMPACT_PRIMARY_MODEL="''${COMPACT_PRIMARY_MODEL:-/Users/amitsheokand/models/Compactor-Qwen3.5-4B-4bit}"
      export COMPACT_PRIMARY_TIMEOUT_S="''${COMPACT_PRIMARY_TIMEOUT_S:-60}"
      export COMPACT_FALLBACK_BASE="''${COMPACT_FALLBACK_BASE:-http://127.0.0.1:8092/v1}"
      export COMPACT_FALLBACK_MODEL="''${COMPACT_FALLBACK_MODEL:-qwen3.5-0.8b}"
      exec ${python}/bin/python3 ${routerSrc}
    '';
  };

  tiny = pkgs.writeShellApplication {
    name = "pi-compact-tiny";
    runtimeInputs = [ pkgs.coreutils pkgs.bash ];
    text = ''
      exec ${pkgs.bash}/bin/bash ${tinySrc}
    '';
  };

  extraProvider = {
    compact = {
      baseUrl = "http://127.0.0.1:8091/v1";
      api = "openai-completions";
      apiKey = "compact-local";
      compat = {
        maxTokensField = "max_tokens";
        supportsDeveloperRole = true;
        supportsReasoningEffort = false;
      };
      models = [
        {
          id = "compactor";
          name = "Compactor";
          reasoning = false;
          input = [ "text" ];
          contextWindow = 16384;
          maxTokens = 4096;
          cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
        }
      ];
    };
  };

  sessionVariables = {
    PI_CC_COMPACT_MODEL = "compact/compactor";
    # Async compact still summarizes with the conversation model (Anvil).
    # That 503s hipfire. Threshold /compact goes through pi-cc-compact instead.
    PI_ASYNC_PREFIX_COMPACTION = "0";
  };

  systemdUserServices = {
    pi-compact-tiny = {
      Unit = {
        Description = "Pi compact tiny Qwen3.5-0.8B (iGPU Vulkan0, not R9700)";
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${tiny}/bin/pi-compact-tiny";
        Restart = "on-failure";
        RestartSec = "3";
        Environment = [
          "HOME=${homeDir}"
          "COMPACT_TINY_GGUF=${homeDir}/.local/share/pi-compact/Qwen3.5-0.8B-Q8_0.gguf"
          "COMPACT_TINY_DEVICE=Vulkan0"
          "GGML_VK_VISIBLE_DEVICES=0"
        ];
      };
      Install.WantedBy = [ "default.target" ];
    };
    pi-compact-router = {
      Unit = {
        Description = "Pi compact router (Mac Compactor :8081, then local tiny)";
        After = [ "network-online.target" "pi-compact-tiny.service" ];
        Wants = [ "pi-compact-tiny.service" ];
      };
      Service = {
        ExecStart = "${router}/bin/pi-compact-router";
        Restart = "on-failure";
        RestartSec = "2";
        Environment = [
          "HOME=${homeDir}"
          "COMPACT_PRIMARY_BASE=http://ai-mac.local:8081/v1"
          "COMPACT_PRIMARY_MODEL=/Users/amitsheokand/models/Compactor-Qwen3.5-4B-4bit"
          "COMPACT_PRIMARY_TIMEOUT_S=60"
          "COMPACT_FALLBACK_BASE=http://127.0.0.1:8092/v1"
          "COMPACT_FALLBACK_MODEL=qwen3.5-0.8b"
        ];
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
in
{
  inherit extraProvider sessionVariables systemdUserServices router tiny;
  packages = [ router tiny ];
  skillFile = skillSrc;
  focusFile = focusFile;
}
