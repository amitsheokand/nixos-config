# Pi ~/.pi/agent/models.json for a local OpenAI-compatible server.
#
# `id` is sent as the API `model` field. MLX crashes if that id is an unknown
# alias (it tries to load it as a new checkpoint). Keep `id` equal to the
# server's real model id; use `name` for the /model picker search string.
{ pkgs, providerId, apiModel, displayName, contextWindow, maxTokens }:

pkgs.writeText "pi-local-models.json" (builtins.toJSON {
  providers = {
    ${providerId} = {
      baseUrl = "http://127.0.0.1:8080/v1";
      api = "openai-completions";
      apiKey = "local";
      compat = {
        supportsDeveloperRole = false;
        supportsReasoningEffort = false;
      };
      models = [ {
        id = apiModel;
        name = displayName;
        reasoning = false;
        input = [ "text" ];
        contextWindow = contextWindow;
        maxTokens = maxTokens;
        cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
      } ];
    };
  };
})
