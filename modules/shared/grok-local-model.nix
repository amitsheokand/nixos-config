# Grok [model.<id>] fragment for /etc/grok/managed_config.toml.
#
# Registers a local OpenAI-compatible server in Grok's /model picker without
# setting GROK_MODELS_BASE_URL (that would replace the cloud catalog).
{ id, apiModel, displayName, description, contextWindow, maxTokens
, baseUrl ? "http://127.0.0.1:8080/v1"
}:

''
[model.${id}]
model = "${apiModel}"
base_url = "${baseUrl}"
name = "${displayName}"
description = "${description}"
api_backend = "chat_completions"
api_key = "local"
context_window = ${toString contextWindow}
max_completion_tokens = ${toString maxTokens}
supports_backend_search = false
''
