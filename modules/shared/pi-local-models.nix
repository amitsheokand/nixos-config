# Pi ~/.pi/agent/models.json for a local OpenAI-compatible server.
#
# `id` is sent as the API `model` field. MLX crashes if that id is an unknown
# alias (it tries to load it as a new checkpoint). Keep Darwin `id` equal to
# the server's real model id; use `name` for the /model picker search string.
#
# Hipfire on the PC sits behind the forge/anvil profile proxy, so those ids
# are real as far as the client is concerned.
{ pkgs
, providerId
, contextWindow
, maxTokens
, apiModel ? ""
, displayName ? providerId
, baseUrl ? "http://127.0.0.1:8080/v1"
, api ? "openai-completions"
, apiKey ? "local"
, supportsDeveloperRole ? false
, supportsReasoningEffort ? false
, reasoning ? false
, extraCompat ? {}
, models ? null
}:

let
  defaultModel = {
    id = apiModel;
    name = displayName;
    inherit reasoning;
    input = [ "text" ];
    inherit contextWindow maxTokens;
    cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
  };
  modelList = if models != null then models else [ defaultModel ];
in
pkgs.writeText "pi-local-models.json" (builtins.toJSON {
  providers = {
    ${providerId} = {
      inherit baseUrl api apiKey;
      compat = {
        inherit supportsDeveloperRole supportsReasoningEffort;
      } // extraCompat;
      models = modelList;
    };
  };
})
