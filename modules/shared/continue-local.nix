# Continue.dev config for the local Qwen3.8 helper (OpenAI-compatible llama-server).
# Cursor Agent / CLI keep the cloud catalog; Continue talks to localhost directly
# (no Cloudflare tunnel needed). Managed by Home Manager on NixOS.
{ contextWindow ? 131072, maxTokens ? 8192, apiBase ? "http://127.0.0.1:8080/v1", model ? "qwen38" }:

''
name: Local Qwen3.8
version: 1.0.0
schema: v1
models:
  - name: qwen38
    provider: openai
    model: ${model}
    apiBase: ${apiBase}
    apiKey: local
    roles:
      - chat
      - edit
      - apply
      - summarize
    capabilities:
      - tool_use
    defaultCompletionOptions:
      contextLength: ${toString contextWindow}
      maxTokens: ${toString maxTokens}
      temperature: 0.6
context:
  - provider: file
  - provider: code
  - provider: diff
  - provider: terminal
  - provider: problems
  - provider: folder
  - provider: codebase
''
