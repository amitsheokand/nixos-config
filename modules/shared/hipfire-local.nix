# Home-Manager fragment: hipfire serve + named profile proxy on the desktop PC.
#
# Does not import hipfire's NixOS module (that rebuilds the Rust workspace and
# overwrites ~/.hipfire/config.toml). Uses the locally built binaries and the
# existing user config. Catalog lives in ./agent-profiles.nix:
#   lanes (forge/anvil/feather) vs backends (ornith/qwen38).
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

  defaultBackendId = profiles.defaultBackend;
  defaultBackend = profiles.backends.${defaultBackendId};
  defaultLane = profiles.defaultLane or profiles.defaultProfile;
  modelsDir = "${homeDir}/.hipfire/models";

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

  jsonBackend = id: backend: {
    tag = backend.tag;
    aliases = backend.aliases or [ id ];
    display_name = backend.displayName;
    description = backend.description;
    context_window = backend.contextWindow or profiles.contextWindow;
    max_tokens = backend.maxTokens or profiles.maxTokens;
    speculation = backend.speculation or [ "off" ];
  } // lib.optionalAttrs (backend ? draftFile) { draft_file = backend.draftFile; };

  jsonLane = _name: profile: {
    display_name = profile.displayName;
    description = profile.description;
    context_window = profile.contextWindow or profiles.contextWindow;
    max_tokens = profile.maxTokens or profiles.maxTokens;
    speculation = profile.speculation or "off";
    defaults = mkDefaults profile;
  };

  profileJson = {
    backend = "http://127.0.0.1:${toString profiles.hipfirePort}";
    backend_model = defaultBackend.tag;
    default_backend = defaultBackendId;
    listen_port = profiles.listenPort;
    backends = lib.mapAttrs jsonBackend profiles.backends;
    profiles = lib.mapAttrs jsonLane profiles.profiles;
  };

  profilesJsonText = builtins.toJSON profileJson;

  proxy = pkgs.writeShellApplication {
    name = "hipfire-profile-proxy";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      export HIPFIRE_PROFILES_JSON=${lib.escapeShellArg profilesJsonText}
      export HIPFIRE_PROFILE_HOST=127.0.0.1
      export HIPFIRE_PROFILE_PORT=${toString profiles.listenPort}
      exec ${pkgs.python3}/bin/python3 ${./scripts/hipfire-profile-proxy.py}
    '';
  };

  draftExport =
    if defaultBackend ? draftFile then ''
      export HIPFIRE_DFLASH_DRAFT="''${HIPFIRE_DFLASH_DRAFT:-${modelsDir}/${defaultBackend.draftFile}}"
    '' else ''
      unset HIPFIRE_DFLASH_DRAFT
    '';

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
      ${draftExport}
      export HIPFIRE_QWEN_MTP="''${HIPFIRE_QWEN_MTP:-0}"
      export HIPFIRE_MODELS_DIR="''${HIPFIRE_MODELS_DIR:-${modelsDir}}"
      export HIPFIRE_DAEMON_BIN="''${HIPFIRE_DAEMON_BIN:-${hipfireDaemon}}"
      export HIP_PATH="${rocm.clr}"
      export HIPFIRE_HIPCC_EXTRA_FLAGS="--rocm-device-lib-path=${rocm.rocm-device-libs}/amdgcn/bitcode"
      export LD_LIBRARY_PATH="${rocmLib}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      cd ${lib.escapeShellArg hipfireRoot}
      exec ${lib.escapeShellArg hipfireBin} serve \
        --model ${lib.escapeShellArg defaultBackend.tag} \
        --kv-mode ${lib.escapeShellArg (defaultBackend.kvMode or "q8")} \
        --idle-timeout 0 \
        "$@"
    '';
  };

  hermesPython = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);

  baseUrl = "http://127.0.0.1:${toString profiles.listenPort}/v1";

  piModel = name: profile: {
    id = name;
    name = profile.displayName or name;
    reasoning = profile.reasoning or true;
    input = [ "text" ];
    contextWindow = profile.contextWindow or profiles.contextWindow;
    maxTokens = profile.maxTokens or profiles.maxTokens;
    cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
  } // lib.optionalAttrs (profile ? thinkingLevelMap) {
    thinkingLevelMap = profile.thinkingLevelMap;
  };

  compositeEntries = lib.flatten (lib.mapAttrsToList (laneId: lane:
    lib.mapAttrsToList (backendId: backend:
      {
        id = "${laneId}/${backendId}";
        displayName = "${lane.displayName} (${backend.displayName})";
        description = "Lane ${laneId} on ${backend.displayName}.";
        contextWindow = lane.contextWindow or backend.contextWindow or profiles.contextWindow;
        maxTokens = lane.maxTokens or backend.maxTokens or profiles.maxTokens;
        reasoning = lane.reasoning or true;
        thinkingLevelMap = lane.thinkingLevelMap or null;
      }
    ) (lib.filterAttrs (id: _: id != defaultBackendId) profiles.backends)
  ) profiles.profiles);

  piModels =
    lib.mapAttrsToList piModel profiles.profiles
    ++ lib.mapAttrsToList (id: backend: piModel id {
      displayName = backend.displayName;
      reasoning = true;
      contextWindow = backend.contextWindow or profiles.contextWindow;
      maxTokens = backend.maxTokens or profiles.maxTokens;
    }) profiles.backends
    ++ map (entry: piModel entry.id {
      displayName = entry.displayName;
      reasoning = entry.reasoning;
      contextWindow = entry.contextWindow;
      maxTokens = entry.maxTokens;
    } // lib.optionalAttrs (entry.thinkingLevelMap != null) {
      thinkingLevelMap = entry.thinkingLevelMap;
    }) compositeEntries;

  grokEntry = { id, displayName, description, contextWindow, maxTokens }:
    import ./grok-local-model.nix {
      inherit id displayName description contextWindow maxTokens;
      apiModel = id;
      baseUrl = baseUrl;
    };

  grokToml =
    lib.concatMapStrings (name:
      let profile = profiles.profiles.${name};
      in grokEntry {
        id = name;
        displayName = profile.displayName;
        description = profile.description;
        contextWindow = profile.contextWindow or profiles.contextWindow;
        maxTokens = profile.maxTokens or profiles.maxTokens;
      }
    ) (builtins.attrNames profiles.profiles)
    + lib.concatMapStrings (name:
      let backend = profiles.backends.${name};
      in grokEntry {
        id = name;
        displayName = backend.displayName;
        description = backend.description;
        contextWindow = backend.contextWindow or profiles.contextWindow;
        maxTokens = backend.maxTokens or profiles.maxTokens;
      }
    ) (builtins.attrNames profiles.backends)
    + lib.concatMapStrings (entry: grokEntry {
      id = entry.id;
      displayName = entry.displayName;
      description = entry.description;
      contextWindow = entry.contextWindow;
      maxTokens = entry.maxTokens;
    }) compositeEntries;

  catalogEnv = ''
    export HIPFIRE_PROFILES_JSON=${lib.escapeShellArg profilesJsonText}
    export AI_BASE_URL=${lib.escapeShellArg baseUrl}
  '';

  hermesMergeScript = ''
    ${catalogEnv}
    ${hermesPython}/bin/python3 ${./scripts/hermes-merge-hipfire-aliases.py} || true
  '';

  zedMergeScript = ''
    ${catalogEnv}
    ${pkgs.python3}/bin/python3 ${./scripts/zed-merge-hipfire.py} || true
  '';

  continueMergeScript = ''
    ${catalogEnv}
    ${hermesPython}/bin/python3 ${./scripts/continue-merge-hipfire.py} || true
  '';

  catalogMergeScript = ''
    rm -f "$HOME/.config/systemd/user/hipfire-serve.service.d/ornith-ar.conf"
    rm -f "$HOME/.config/systemd/user/hipfire-profile-proxy.service.d/ornith-ar.conf"
  '' + hermesMergeScript + zedMergeScript + continueMergeScript;
in
{
  inherit profiles baseUrl proxy serve grokToml profileJson
    hermesMergeScript zedMergeScript continueMergeScript catalogMergeScript;

  sessionVariables = {
    AI_BASE_URL = baseUrl;
    AI_MODEL = defaultLane;
    AI_CONTEXT_WINDOW = toString profiles.contextWindow;
    AI_MAX_TOKENS = toString profiles.maxTokens;
    GROK_LOCAL_MODEL = defaultLane;
    GROK_LOCAL_BASE_URL = baseUrl;
  };

  packages = [ proxy serve ];

  piLocalSettings = {
    defaultProvider = "hipfire";
    defaultModel = defaultLane;
    model = defaultLane;
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
    models = piModels;
  };

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
          "HIPFIRE_QWEN_MTP=0"
        ];
      };
      Install.WantedBy = [ "default.target" ];
    };

    hipfire-profile-proxy = {
      Unit = {
        Description = "Lane/backend OpenAI catalog proxy in front of hipfire :${toString profiles.hipfirePort}";
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
}
