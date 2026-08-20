// Register stealth/ox-alpha on OpenRouter as a pi provider.
//
// The API key is resolved from the OPENROUTER_API_KEY env var (sourced into
// the shell from ~/.config/openrouter.env via nixos-config home-manager).
// Never hardcode the key here — this file may be shared/committed.
//
// Model metadata fetched from OpenRouter's /api/v1/models endpoint:
//   - context_length:   1,048,576
//   - max output:       131,072
//   - pricing:          $0 prompt / $0 completion (free)
//   - modalities:       text + image -> text
//   - reasoning:        mandatory, supported efforts max/high/low
//
// After adding this file, run `pi --list-models` or start pi and pick the
// model via /model. Use /reload to hot-reload after edits.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.registerProvider("openrouter", {
    name: "OpenRouter",
    baseUrl: "https://openrouter.ai/api/v1",
    apiKey: "$OPENROUTER_API_KEY",
    api: "openai-completions",
    // OpenRouter attributes requests with these optional headers.
    headers: {
      "X-Title": "pi",
      "HTTP-Referer": "https://openrouter.ai",
    },
    models: [
      {
        id: "stealth/ox-alpha",
        name: "Ox Alpha (OpenRouter)",
        reasoning: true,
        // Ox Alpha supports only max/high/low reasoning efforts.
        // null hides unsupported pi levels (off, minimal, medium, xhigh).
        thinkingLevelMap: {
          off: null,
          minimal: null,
          low: "low",
          medium: null,
          high: "high",
          xhigh: null,
          max: "max",
        },
        input: ["text", "image"],
        // Free model: all costs zero so usage tracking stays accurate.
        cost: {
          input: 0,
          output: 0,
          cacheRead: 0,
          cacheWrite: 0,
        },
        contextWindow: 1048576,
        maxTokens: 131072,
        compat: {
          // OpenRouter expects `reasoning: { effort }` shaped controls.
          thinkingFormat: "openrouter",
          supportsReasoningEffort: true,
          // OpenRouter Chat Completions uses max_tokens (not max_completion_tokens).
          maxTokensField: "max_tokens",
          supportsDeveloperRole: false,
        },
      },
    ],
  });
}
