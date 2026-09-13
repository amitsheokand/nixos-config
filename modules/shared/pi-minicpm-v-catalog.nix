# Pi + Grok/session catalog for MiniCPM-V 4.5 (visual oracle).
# Not hipfire. PC loopback :8093; LAN clients use nixos.local:8093.
{
  lib,
  baseUrl ? "http://127.0.0.1:8093/v1",
  extraProviders ? {},
}:

let
  longctxLan = import ./pi-longctx.nix { baseUrl = "http://ai-mac.local:8080/v1"; };
  compactLan = import ./pi-compactor.nix { baseUrl = "http://ai-mac.local:8081/v1"; };

  grokToml = import ./grok-local-model.nix {
    id = "minicpm-v-4.5";
    apiModel = "minicpm-v-4.5";
    displayName = "MiniCPM-V 4.5";
    description = "R9700 visual oracle (llama.cpp Vulkan). Screenshots/XAML; Pi chat stays longctx.";
    contextWindow = 8192;
    maxTokens = 2048;
    inherit baseUrl;
    apiKey = "local";
  };

  piLocalModels = {
    providerId = "minicpm-v";
    inherit baseUrl;
    apiKey = "minicpm-v-local";
    api = "openai-completions";
    supportsDeveloperRole = false;
    supportsReasoningEffort = false;
    extraCompat = {
      maxTokensField = "max_tokens";
    };
    extraProviders = {
      mlx-compact = compactLan.provider;
      compact = compactLan.provider;
      longctx = longctxLan.provider;
    } // extraProviders;
    contextWindow = 8192;
    maxTokens = 2048;
    models = [
      {
        id = "minicpm-v-4.5";
        name = "MiniCPM-V 4.5";
        reasoning = false;
        input = [ "text" "image" ];
        contextWindow = 8192;
        maxTokens = 2048;
        cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
      }
    ];
  };

  piLocalSettings = {
    defaultProvider = "longctx";
    defaultModel = "longctx";
    model = "longctx";
    defaultThinkingLevel = "low";
  };

  sessionVariables = {
    AI_BASE_URL = baseUrl;
    AI_MODEL = "minicpm-v-4.5";
    AI_CONTEXT_WINDOW = "8192";
    AI_MAX_TOKENS = "2048";
    GROK_LOCAL_MODEL = "minicpm-v-4.5";
    GROK_LOCAL_BASE_URL = baseUrl;
  } // compactLan.sessionVariables;
in
{
  inherit grokToml piLocalModels piLocalSettings sessionVariables;
}
