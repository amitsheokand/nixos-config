// Project large tool results after two full provider sends.
// Idea from NVIDIA SoL-Pi ObservationPack V2 (MIT): 10 KiB threshold, two
// full sends, then a head/tail placeholder. This is our Pi 0.85 context
// hook — not the SoL-Pi package. Recall is one-grep / sed on the archive,
// not obs_recall. Headroom stays for Cursor/Claude/Codex. Fail-open.
import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import {
  getAgentDir,
  type ExtensionAPI,
  type ExtensionContext,
} from "@earendil-works/pi-coding-agent";

export const THRESHOLD_BYTES = 10 * 1024;
export const FULL_SENDS = 2;
export const HEAD_BYTES = 2048;
export const TAIL_BYTES = 1536;

export const LIKELY_SECRET =
  /(?:api[_-]?key|authorization|bearer|access[_-]?token|secret)[^\n]{0,32}[=:][^\n]+/i;
export const SKIP_LINE =
  /^(?:advait_epr_v1|advait_obs_v1)\b/;

type Content = { type: string; text?: string };

type ToolResult = {
  role?: string;
  toolName?: string;
  toolCallId?: string;
  isError?: boolean;
  content?: Content[];
};

export function textOf(content: Content[] | undefined): string {
  return (content ?? [])
    .map((part) => (typeof part.text === "string" ? part.text : ""))
    .join("\n");
}

export function isPureTextResult(message: ToolResult): boolean {
  return (
    message.role === "toolResult" &&
    Array.isArray(message.content) &&
    message.content.length > 0 &&
    message.content.every((block) => block.type === "text")
  );
}

export function isCursorEditDiff(body: string): boolean {
  const looksDiff =
    /\n@@\s+-\d+/.test(body) &&
    (/^edit\s+\S/i.test(body) || /^---\s+(?:a\/|\/dev\/null)/m.test(body));
  if (!looksDiff) return false;
  return !/\berror\[E\d+]|FAILED\.|panic!|Compiling\s+\S+\sv\d/i.test(body);
}

export function shouldSkip(body: string): boolean {
  if (Buffer.byteLength(body, "utf8") <= THRESHOLD_BYTES) return true;
  if (LIKELY_SECRET.test(body)) return true;
  if (isCursorEditDiff(body)) return true;
  const first = body.split(/\r?\n/, 1)[0] ?? "";
  return SKIP_LINE.test(first) || body.includes("\nadvait_epr_v1\n");
}

export function placeholderFor(opts: {
  id: string;
  tool: string;
  bytes: number;
  lines: number;
  path: string;
  body: string;
}): string {
  const buf = Buffer.from(opts.body, "utf8");
  const head = buf.subarray(0, HEAD_BYTES).toString("utf8");
  const tail =
    buf.length > TAIL_BYTES
      ? buf.subarray(buf.length - TAIL_BYTES).toString("utf8")
      : "";
  const dir = opts.path.slice(0, opts.path.lastIndexOf("/"));
  return [
    "advait_obs_v1",
    `id=${opts.id}`,
    `tool=${opts.tool}`,
    `source_bytes=${opts.bytes}`,
    `source_lines=${opts.lines}`,
    `source_artifact=${opts.path}`,
    `full_sends=${FULL_SENDS}`,
    `recall=one-grep rg ${dir} -- <literal>  OR  sed -n '1,80p' ${opts.path}`,
    "preview_head:",
    head,
    "preview_tail:",
    tail,
  ].join("\n");
}

function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function sessionIdOf(ctx: ExtensionContext): string {
  const manager = ctx.sessionManager as {
    getSessionId?: () => string | undefined;
    getSessionFile?: () => string | undefined;
  };
  return manager.getSessionId?.() || manager.getSessionFile?.() || "ephemeral";
}

async function archiveBody(
  sessionId: string,
  id: string,
  body: string,
): Promise<string> {
  const dir = join(getAgentDir(), "obs", sessionId);
  await mkdir(dir, { recursive: true });
  const path = join(dir, `${id}.log`);
  await writeFile(path, body, "utf8");
  return path;
}

export default function (pi: ExtensionAPI) {
  pi.on("context", async (event, ctx) => {
    try {
      const messages = event.messages as ToolResult[];
      const priorAssistant: number[] = new Array(messages.length);
      let assistants = 0;
      for (let i = messages.length - 1; i >= 0; i -= 1) {
        priorAssistant[i] = assistants;
        if (messages[i]?.role === "assistant") assistants += 1;
      }

      const session = sessionIdOf(ctx).replace(/[/\\]/g, "_");
      const projected = [...messages];

      for (let i = 0; i < messages.length; i += 1) {
        const message = messages[i];
        if (!isPureTextResult(message)) continue;
        const body = textOf(message.content);
        if (shouldSkip(body)) continue;

        const tool = message.toolName || "tool";
        const callId = message.toolCallId || `idx${i}`;
        const id = `obs_${sha256(`${tool}\0${callId}\0${sha256(body)}`).slice(0, 24)}`;
        let path: string;
        try {
          path = await archiveBody(session, id, body);
        } catch {
          continue;
        }

        if ((priorAssistant[i] ?? 0) < FULL_SENDS) continue;

        projected[i] = {
          ...message,
          content: [
            {
              type: "text",
              text: placeholderFor({
                id,
                tool,
                bytes: Buffer.byteLength(body, "utf8"),
                lines: body.split(/\r?\n/).length,
                path,
                body,
              }),
            },
          ],
        };
      }

      return { messages: projected };
    } catch {
      return undefined;
    }
  });
}
