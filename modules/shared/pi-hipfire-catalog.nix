# Pi provider payload for the hipfire catalog proxy (lanes + backends).
# Desktop uses 127.0.0.1; Mac/odie/vaayu use http://nixos.local:8080/v1.
{ lib, baseUrl }:

let
  profiles = import ./agent-profiles.nix;
  defaultBackendId = profiles.defaultBackend;
  visibleBackends = lib.filterAttrs (_: backend: backend.available or true) profiles.backends;
  compactLan = import ./pi-compactor.nix {
    baseUrl = "http://ai-mac.local:8081/v1";
  };

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
        contextWindow = lib.min
          (backend.contextWindow or profiles.contextWindow)
          (backend.maxSeq or 65536);
        maxTokens = lib.min
          (lane.maxTokens or profiles.maxTokens)
          (backend.maxTokens or profiles.maxTokens);
        reasoning = lane.reasoning or true;
        thinkingLevelMap = lane.thinkingLevelMap or null;
      }
    ) (lib.filterAttrs (id: _: id != (lane.backend or defaultBackendId)) visibleBackends)
  ) profiles.profiles);

  piModels =
    lib.mapAttrsToList piModel profiles.profiles
    ++ lib.mapAttrsToList (id: backend: piModel id {
      displayName = backend.displayName;
      reasoning = true;
      contextWindow = backend.contextWindow or profiles.contextWindow;
      maxTokens = backend.maxTokens or profiles.maxTokens;
    }) visibleBackends
    ++ map (entry: piModel entry.id {
      displayName = entry.displayName;
      reasoning = entry.reasoning;
      contextWindow = entry.contextWindow;
      maxTokens = entry.maxTokens;
    } // lib.optionalAttrs (entry.thinkingLevelMap != null) {
      thinkingLevelMap = entry.thinkingLevelMap;
    }) compositeEntries;

  provider = {
    inherit baseUrl;
    api = "openai-completions";
    apiKey = "hipfire-local";
    compat = {
      supportsDeveloperRole = true;
      supportsReasoningEffort = true;
      supportsUsageInStreaming = true;
      maxTokensField = "max_tokens";
    };
    models = piModels;
  };

  piLocalModels = {
    providerId = "hipfire";
    inherit baseUrl;
    apiKey = "hipfire-local";
    api = "openai-completions";
    supportsDeveloperRole = true;
    supportsReasoningEffort = true;
    extraCompat = {
      supportsUsageInStreaming = true;
      maxTokensField = "max_tokens";
    };
    extraProviders = {
      mlx-compact = compactLan.provider;
      # Same server; hermes `compact/compactor` works on odie/vaayu/Mac.
      compact = compactLan.provider;
    };
    contextWindow = profiles.contextWindow;
    maxTokens = profiles.maxTokens;
    models = piModels;
  };

  piLocalSettings = {
    defaultProvider = "hipfire";
    defaultModel = profiles.defaultLane;
    model = profiles.defaultLane;
    defaultThinkingLevel = "medium";
  };

  sessionVariables = {
    AI_BASE_URL = baseUrl;
    AI_MODEL = profiles.defaultLane;
    AI_CONTEXT_WINDOW = toString (
      profiles.profiles.${profiles.defaultLane}.contextWindow or profiles.contextWindow
    );
    AI_MAX_TOKENS = toString (
      profiles.profiles.${profiles.defaultLane}.maxTokens or profiles.maxTokens
    );
    GROK_LOCAL_MODEL = profiles.defaultLane;
    GROK_LOCAL_BASE_URL = baseUrl;
  } // compactLan.sessionVariables;
in
{
  inherit piModels provider piLocalModels piLocalSettings compositeEntries sessionVariables;
}
