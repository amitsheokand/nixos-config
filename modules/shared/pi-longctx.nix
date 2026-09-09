# Pi provider for MiniCPM5-2B long-context lane (Mac MLX :8080).
# Coordinator / herding / mechanical. Not hipfire / Anvil.
#
# Local Mac: http://127.0.0.1:8080/v1
# PC / vaayu: http://ai-mac.local:8080/v1
# Server aliases id `longctx` (and `minicpm`) to the fused MLX path.
{ baseUrl }:

{
  provider = {
    inherit baseUrl;
    api = "openai-completions";
    apiKey = "local";
    compat = {
      supportsDeveloperRole = false;
      supportsReasoningEffort = false;
      maxTokensField = "max_tokens";
    };
    models = [
      {
        id = "longctx";
        name = "MiniCPM5-2B longctx";
        reasoning = false;
        input = [ "text" ];
        contextWindow = 65536;
        maxTokens = 8192;
        cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
      }
    ];
  };
}
