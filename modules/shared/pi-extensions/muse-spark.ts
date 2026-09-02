// Register Meta Model API Muse Spark as a Pi provider.
//
// Key from MODEL_API_KEY or META_API_KEY (sourced from ~/.config/meta.env).
// Never hardcode the key — this file is committed.
//
// Pi speaks Chat Completions (`openai-completions`) via muse-spark-proxy
// on :8082, which uniquifies Spark's reused tool_call_id `call_0`. Encrypted
// reasoning is not replayed on this surface; prefer `muse` (Muse Code) or
// OpenCode's `@ai-sdk/openai` adapter for multi-turn reasoning continuity.
// Docs: https://dev.meta.ai/docs/coding-agents/

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.registerProvider("meta", {
    name: "Meta Model API",
    baseUrl: "http://127.0.0.1:8082/v1",
    apiKey: "$MODEL_API_KEY",
    api: "openai-completions",
    models: [
      {
        id: "muse-spark-1.2",
        name: "Muse Spark 1.2",
        reasoning: true,
        thinkingLevelMap: {
          off: null,
          minimal: "low",
          low: "low",
          medium: "medium",
          high: "high",
          xhigh: "high",
          max: "high",
        },
        input: ["text", "image"],
        cost: {
          input: 0,
          output: 0,
          cacheRead: 0,
          cacheWrite: 0,
        },
        contextWindow: 1048576,
        maxTokens: 131072,
        compat: {
          supportsReasoningEffort: true,
          maxTokensField: "max_tokens",
          supportsDeveloperRole: false,
        },
      },
    ],
  });
}
