# Pi provider for Compactor-Qwen3.5-4B on Mac MLX :8081.
# Compact traffic only. Never hipfire / Anvil.
#
# PI_CC_COMPACT_MODEL=mlx-compact/compactor
# Server aliases id `compactor` to the fused MLX path (mlx-lm rejects unknown ids).
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
        id = "compactor";
        name = "compactor";
        reasoning = false;
        input = [ "text" ];
        contextWindow = 16384;
        maxTokens = 4096;
        cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
      }
    ];
  };
  sessionVariables = {
    PI_CC_COMPACT_MODEL = "mlx-compact/compactor";
  };
}
