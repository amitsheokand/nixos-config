// Optional then_run on edit/write, plus gate_edit/gate_write for packets
// that require a Gate. `--kind pi` only; paid Cursor/Muse are Herdr kinds,
// not pi-cursor-sdk. Idea from NVIDIA SoL-Pi (MIT); this is our Pi 0.85
// wrapper — not the SoL-Pi package.
//
// 14 Sep: Cursor called gate_edit 16× but then_run never ran. JSONL kept
// then_run on the toolCall while execute returned in 2ms — prepareArguments
// on the inner edit/write tool drops unknown keys. Re-attach then_run after
// prepare. gate_* reject a missing then_run so the tool cannot be a second Edit.
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

function isGate(name: string): boolean {
  return name === "gate_edit" || name === "gate_write";
}

function withThenRunSchema(schema: unknown, required: boolean): unknown {
  const cloned = JSON.parse(
    JSON.stringify(schema ?? { type: "object", properties: {} }),
  ) as {
    properties?: Record<string, unknown>;
    required?: string[];
  };
  cloned.properties = cloned.properties ?? {};
  cloned.properties.then_run = {
    type: "string",
    description: required
      ? "REQUIRED. Shell Gate after this mutation succeeds (PACKET.md Gate, e.g. cargo test -p <crate> --lib). Intermediate hunks use host Edit; this tool exists to fuse the Gate. Calls without then_run are rejected."
      : "Shell command to run after this mutation succeeds. Prefer PACKET.md Gate, e.g. cargo test -p <crate> --lib. Prefer this over a separate bash call.",
  };
  if (required) {
    const req = Array.isArray(cloned.required) ? [...cloned.required] : [];
    if (!req.includes("then_run")) req.push("then_run");
    cloned.required = req;
  }
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

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? { ...(value as Record<string, unknown>) }
    : {};
}

function preserveThenRun(
  prepare: MutationTool["prepareArguments"],
  args: unknown,
): Record<string, unknown> {
  const { thenRun, rest } = stripThenRun(args);
  const prepared = prepare ? prepare(rest) : rest;
  const rec = asRecord(prepared);
  if (thenRun) rec.then_run = thenRun;
  return rec;
}

function textOf(result: { content?: Content[] } | undefined): string {
  return (result?.content ?? [])
    .map((part) => (typeof part.text === "string" ? part.text : ""))
    .join("\n");
}

function looksFailed(result: { content?: Content[] } | undefined): boolean {
  const text = textOf(result).toLowerCase();
  // rustc warning noise contains "error"/"failed"; a green test is success.
  if (
    /test result:\s*ok/.test(text) ||
    /\d+ passed;\s*0 failed/.test(text)
  ) {
    return false;
  }
  return (
    text.includes("error") ||
    text.includes("failed") ||
    text.includes("not found") ||
    text.includes("no match") ||
    text.includes("could not find") ||
    text.includes("must be unique") ||
    text.includes("must have required")
  );
}

function missingThenRunResult(name: string): { content: Content[] } {
  return {
    content: [
      {
        type: "text",
        text:
          `error: ${name} requires then_run=<PACKET.md Gate> (e.g. cargo test -p <crate> --lib). ` +
          `Host Edit is for intermediate hunks. This tool exists to fuse the Gate on the same turn. ` +
          `Do not call ${name} without then_run.`,
      },
    ],
  };
}

function fuse(
  pi: ExtensionAPI,
  name: string,
  factory: (cwd: string) => MutationTool,
) {
  const bootstrap = factory(".");
  const requireThen = isGate(name);
  const cursorHost = requireThen
    ? " REQUIRED. Cursor host Edit/Shell cannot take then_run."
    : "";
  pi.registerTool({
    name,
    label: name,
    description: bootstrap.description ?? name,
    parameters: withThenRunSchema(bootstrap.parameters, requireThen),
    prepareArguments: (args) =>
      preserveThenRun(bootstrap.prepareArguments, args),
    promptGuidelines: [
      requireThen
        ? `${name} REQUIRES then_run on every call (PACKET.md Gate). Intermediate edits: host Edit. Last hunk + Gate: this tool. Example: then_run="cargo test -p <crate> --lib". Calls without then_run are rejected.${cursorHost}`
        : `After ${name}, if you would immediately bash a test/build/check of that file, pass then_run on the same call instead of a second bash. Example: then_run="cargo test -p <crate> --lib". PACKET.md Gate is the default command.`,
    ],
    async execute(toolCallId, params, signal, onUpdate, ctx) {
      const { thenRun, rest } = stripThenRun(params);
      if (requireThen && !thenRun) return missingThenRunResult(name);
      const built = factory(ctx.cwd);
      const result = await built.execute(toolCallId, rest, signal, onUpdate);
      if (!thenRun || looksFailed(result)) return result;
      const bash = createBashTool(ctx.cwd);
      // Pi bash has no direnv allow / cargo. Host Cursor Shell does.
      // Flake worktrees: nix develop. Else run as-is.
      const wrapped =
        `[ -f flake.nix ] && nix develop --command bash -lc ${JSON.stringify(thenRun)} || ( ${thenRun} )`;
      const cmd = await bash.execute(
        `${toolCallId}-then`,
        { command: wrapped },
        signal,
        onUpdate,
      );
      const marker = looksFailed(cmd)
        ? "[then_run:failed]"
        : "[then_run:succeeded]";
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
      // Extra names so a packet can require a Gate without colliding with
      // host Edit on native Cursor/Muse seats (those seats are --kind, not a
      // Pi wrap).
      fuse(pi, "gate_edit", createEditTool);
      fuse(pi, "gate_write", createWriteTool);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      ctx.ui.notify(`action-fusion skipped: ${message}`, "warning");
    }
  });
}
