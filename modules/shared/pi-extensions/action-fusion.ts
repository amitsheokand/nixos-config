// Optional then_run on edit/write so a test/build/check runs in the same
// tool turn. Idea from NVIDIA SoL-Pi (MIT); this is our Pi 0.85 wrapper
// around createEditTool/createWriteTool/createBashTool — not the SoL-Pi
// package. Compaction stays /compact + Headroom; do not enable SoL-Pi OCC.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  createBashTool,
  createEditTool,
  createWriteTool,
} from "@earendil-works/pi-coding-agent";

type Content = { type: string; text?: string };

type MutationTool = {
  description?: string;
  parameters?: unknown;
  prepareArguments?: (args: unknown) => unknown;
  execute: (
    toolCallId: string,
    params: unknown,
    signal: AbortSignal | undefined,
    onUpdate: unknown,
  ) => Promise<{ content?: Content[]; details?: unknown }>;
};

function withThenRunSchema(schema: unknown): unknown {
  const cloned = JSON.parse(
    JSON.stringify(schema ?? { type: "object", properties: {} }),
  ) as { properties?: Record<string, unknown> };
  cloned.properties = cloned.properties ?? {};
  cloned.properties.then_run = {
    type: "string",
    description:
      "Shell command to run after this mutation succeeds (test, build, or check this file). Prefer this over a separate bash call.",
  };
  return cloned;
}

function stripThenRun(params: unknown): {
  thenRun: string;
  rest: Record<string, unknown>;
} {
  const rec =
    params && typeof params === "object"
      ? { ...(params as Record<string, unknown>) }
      : {};
  const raw = rec.then_run;
  delete rec.then_run;
  const thenRun = typeof raw === "string" ? raw.trim() : "";
  return { thenRun, rest: rec };
}

function textOf(result: { content?: Content[] } | undefined): string {
  return (result?.content ?? [])
    .map((part) => (typeof part.text === "string" ? part.text : ""))
    .join("\n");
}

function looksFailed(result: { content?: Content[] } | undefined): boolean {
  const text = textOf(result).toLowerCase();
  return (
    text.includes("error") ||
    text.includes("failed") ||
    text.includes("not found") ||
    text.includes("no match")
  );
}

function fuse(
  pi: ExtensionAPI,
  name: "edit" | "write",
  factory: (cwd: string) => MutationTool,
) {
  const bootstrap = factory(".");
  pi.registerTool({
    name,
    label: name,
    description: bootstrap.description ?? name,
    parameters: withThenRunSchema(bootstrap.parameters),
    prepareArguments: bootstrap.prepareArguments,
    promptGuidelines: [
      `After ${name}, if you would immediately bash a test/build/check of that file, pass then_run on the same call instead of a second bash.`,
    ],
    async execute(toolCallId, params, signal, onUpdate, ctx) {
      const { thenRun, rest } = stripThenRun(params);
      const built = factory(ctx.cwd);
      const result = await built.execute(toolCallId, rest, signal, onUpdate);
      if (!thenRun || looksFailed(result)) return result;
      const bash = createBashTool(ctx.cwd);
      const cmd = await bash.execute(
        `${toolCallId}-then`,
        { command: thenRun },
        signal,
        onUpdate,
      );
      const marker = looksFailed(cmd) ? "[then_run:failed]" : "[then_run:succeeded]";
      return {
        ...result,
        content: [
          ...(result.content ?? []),
          {
            type: "text",
            text: `\n${marker} ${thenRun}\n${textOf(cmd)}`,
          },
        ],
        details: {
          ...(typeof result.details === "object" && result.details
            ? result.details
            : {}),
          then_run: thenRun,
        },
      };
    },
  });
}

export default function (pi: ExtensionAPI) {
  let registered = false;
  pi.on("session_start", (_event, ctx) => {
    if (registered) return;
    registered = true;
    try {
      fuse(pi, "edit", createEditTool);
      fuse(pi, "write", createWriteTool);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      ctx.ui.notify(`action-fusion skipped: ${message}`, "warning");
    }
  });
}
