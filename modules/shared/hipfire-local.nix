# Home-Manager fragment: hipfire serve + named profile proxy on the desktop PC.
#
# Does not import hipfire's NixOS module (that rebuilds the Rust workspace and
# overwrites ~/.hipfire/config.toml). Uses the locally built binaries and the
# existing user config. Profile names live in ./agent-profiles.nix.
{
  pkgs,
  lib,
  user,
}:

let
  profiles = import ./agent-profiles.nix;
  homeDir = "/home/${user}";
  hipfireRoot = "${homeDir}/dev/hipfire";
  hipfireBin = "${hipfireRoot}/target/release/hipfire";
  hipfireDaemon = "${hipfireRoot}/target/release/daemon";
  rocm = pkgs.rocmPackages;
  rocmLib = lib.makeLibraryPath [
    rocm.clr
    rocm.rocm-runtime
    rocm.rocm-comgr
    rocm.rocprofiler-register
  ];

  mkDefaults = profile:
    let thinking = profile.thinking or true;
    in {
      chat_template_kwargs = {
        enable_thinking = thinking;
      } // lib.optionalAttrs thinking { preserve_thinking = true; };
    }
    // lib.optionalAttrs (profile ? effort) { reasoning_effort = profile.effort; }
    // lib.optionalAttrs (profile ? temperature) { temperature = profile.temperature; }
    // lib.optionalAttrs (profile ? presencePenalty) { presence_penalty = profile.presencePenalty; }
    // lib.optionalAttrs (profile ? speculation) { speculation = profile.speculation; };

  profileJson = {
    backend = "http://127.0.0.1:${toString profiles.hipfirePort}";
    backend_model = profiles.backendModel;
    listen_port = profiles.listenPort;
    profiles = lib.mapAttrs (_name: profile: {
      display_name = profile.displayName;
      description = profile.description;
      context_window = profile.contextWindow or profiles.contextWindow;
      defaults = mkDefaults profile;
    }) profiles.profiles;
  };

  proxy = pkgs.writeShellApplication {
    name = "hipfire-profile-proxy";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      export HIPFIRE_PROFILES_JSON=${lib.escapeShellArg (builtins.toJSON profileJson)}
      export HIPFIRE_PROFILE_HOST=127.0.0.1
      export HIPFIRE_PROFILE_PORT=${toString profiles.listenPort}
      exec ${pkgs.python3}/bin/python3 ${./scripts/hipfire-profile-proxy.py}
    '';
  };

  serve = pkgs.writeShellApplication {
    name = "hipfire-serve-local";
    runtimeInputs = [ rocm.clr ];
    text = ''
      set -euo pipefail
      if [[ ! -x ${lib.escapeShellArg hipfireBin} ]]; then
        echo "hipfire-serve-local: missing ${hipfireBin}" >&2
        echo "Build with: cd ${hipfireRoot} && nix develop -c cargo build --release" >&2
        exit 127
      fi
      export HIPFIRE_DFLASH_DRAFT="''${HIPFIRE_DFLASH_DRAFT:-${homeDir}/.hipfire/models/qwen38-27b-dflash2.hfq}"
      export HIPFIRE_QWEN_MTP="''${HIPFIRE_QWEN_MTP:-0}"
      export HIPFIRE_MODELS_DIR="''${HIPFIRE_MODELS_DIR:-${homeDir}/.hipfire/models}"
      export HIPFIRE_DAEMON_BIN="''${HIPFIRE_DAEMON_BIN:-${hipfireDaemon}}"
      export HIP_PATH="${rocm.clr}"
      export HIPFIRE_HIPCC_EXTRA_FLAGS="--rocm-device-lib-path=${rocm.rocm-device-libs}/amdgcn/bitcode"
      export LD_LIBRARY_PATH="${rocmLib}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      cd ${lib.escapeShellArg hipfireRoot}
      exec ${lib.escapeShellArg hipfireBin} serve --model ${lib.escapeShellArg profiles.backendModel} "$@"
    '';
  };

  hermesPython = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);

  baseUrl = "http://127.0.0.1:${toString profiles.listenPort}/v1";

  piModel = name: profile: {
    id = name;
    name = profile.displayName;
    reasoning = profile.reasoning or true;
    input = [ "text" ];
    contextWindow = profile.contextWindow or profiles.contextWindow;
    maxTokens = profile.maxTokens or profiles.maxTokens;
    cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
  } // lib.optionalAttrs (profile ? thinkingLevelMap) {
    thinkingLevelMap = profile.thinkingLevelMap;
  };
in
{
  inherit profiles baseUrl proxy serve;

  sessionVariables = {
    AI_BASE_URL = baseUrl;
    AI_MODEL = profiles.defaultProfile;
    AI_CONTEXT_WINDOW = toString profiles.contextWindow;
    AI_MAX_TOKENS = toString profiles.maxTokens;
    GROK_LOCAL_MODEL = profiles.defaultProfile;
    GROK_LOCAL_BASE_URL = baseUrl;
  };

  packages = [ proxy serve ];

  piLocalSettings = {
    defaultProvider = "hipfire";
    defaultModel = profiles.defaultProfile;
    model = profiles.defaultProfile;
    defaultThinkingLevel = "medium";
  };

  piLocalModels = {
    providerId = "hipfire";
    baseUrl = baseUrl;
    apiKey = "hipfire-local";
    api = "openai-completions";
    supportsDeveloperRole = true;
    supportsReasoningEffort = true;
    extraCompat = {
      supportsUsageInStreaming = true;
      maxTokensField = "max_tokens";
    };
    contextWindow = profiles.contextWindow;
    maxTokens = profiles.maxTokens;
    models = lib.mapAttrsToList piModel profiles.profiles;
  };

  grokToml = lib.concatMapStrings (name:
    let profile = profiles.profiles.${name};
    in import ./grok-local-model.nix {
      id = name;
      apiModel = name;
      displayName = profile.displayName;
      description = profile.description;
      contextWindow = profile.contextWindow or profiles.contextWindow;
      maxTokens = profile.maxTokens or profiles.maxTokens;
      baseUrl = baseUrl;
    }
  ) (builtins.attrNames profiles.profiles);

  systemdUserServices = {
    hipfire-serve = {
      Unit = {
        Description = "hipfire serve (local cargo build, existing ~/.hipfire config)";
        After = [ "graphical-session.target" ];
        StartLimitIntervalSec = 300;
        StartLimitBurst = 3;
      };
      Service = {
        ExecStart = "${serve}/bin/hipfire-serve-local";
        Restart = "on-failure";
        RestartSec = "5";
        TimeoutStartSec = "0";
        Environment = [
          "HOME=${homeDir}"
          "HIP_VISIBLE_DEVICES=0"
          "HIPFIRE_DFLASH_DRAFT=${homeDir}/.hipfire/models/qwen38-27b-dflash2.hfq"
          "HIPFIRE_QWEN_MTP=0"
        ];
      };
      Install.WantedBy = [ "default.target" ];
    };

    hipfire-profile-proxy = {
      Unit = {
        Description = "Forge/Anvil/Feather OpenAI profile proxy in front of hipfire :${toString profiles.hipfirePort}";
        After = [ "hipfire-serve.service" ];
        Wants = [ "hipfire-serve.service" ];
      };
      Service = {
        ExecStart = "${proxy}/bin/hipfire-profile-proxy";
        Restart = "on-failure";
        RestartSec = "2";
        Environment = [ "HOME=${homeDir}" ];
      };
      Install.WantedBy = [ "default.target" ];
    };
  };

  hermesMergeScript = ''
    ${hermesPython}/bin/python3 ${./scripts/hermes-merge-hipfire-aliases.py} || true
  '';
}
