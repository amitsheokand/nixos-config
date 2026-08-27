# Pi provider payload for the hipfire catalog proxy (lanes + backends).
# Desktop uses 127.0.0.1; Mac/odie/vaayu use http://nixos.local:8080/v1.
{ lib, baseUrl }:

let
  profiles = import ./agent-profiles.nix;
  defaultBackendId = profiles.defaultBackend;

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
in
{
  inherit piModels provider piLocalModels piLocalSettings compositeEntries;
}
