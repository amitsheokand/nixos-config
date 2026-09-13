// Evidence-preserving reducer for diagnostic bash / then_run logs.
// Local only: regex scout first, then compact/compactor on :8091.
// Fail-open. Never overflow, Grok, Muse, or China-hosted. Not the SoL-Pi package.
import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import {
  getAgentDir,
  type ExtensionAPI,
  type ExtensionContext,
} from "@earendil-works/pi-coding-agent";

const MIN_BYTES = 4096;
const MAX_SCOUT_LINES = 12;
const MAX_QUOTE = 600;
// Compactor :8091 accepts 12k input tokens. ~4 chars/token on ASCII logs.
const CLIP_HEAD = 20000;
const CLIP_TAIL = 12000;
const PREVIEW_HEAD = 2048;
const PREVIEW_TAIL = 1536;
const LLM_TIMEOUT_MS = 60_000;
const COMPACT_URLS = [
  "http://127.0.0.1:8091/v1/chat/completions",
  "http://127.0.0.1:8081/v1/chat/completions",
];

// Keep in sync with modules/shared/scripts/test_epr.py
export const DIAGNOSTIC_COMMAND =
  /(?:^|[;&|()\s])(?:cargo(?:\s+(?:build|test|check|nextest))?|cmake\s+--build|ctest|ninja|make|pytest|python(?:3)?\s+-m\s+(?:pytest|unittest|py_compile)|npm\s+test|pnpm\s+test|yarn\s+test|go\s+test|bazel\s+test)(?:\s|$)/i;
export const FAILURE_SIGNAL =
  /error|failed|failure|fatal|exception|panic|timeout|unsolved|type mismatch|assert/i;
export const LIKELY_SECRET =
  /(?:api[_-]?key|authorization|bearer|access[_-]?token|secret)[^\n]{0,32}[=:][^\n]+/i;

type Content = { type: string; text?: string };

function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function textOf(content: Content[] | undefined): string {
  return (content ?? [])
    .map((part) => (typeof part.text === "string" ? part.text : ""))
    .join("\n");
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

export function commandOf(event: {
  toolName?: string;
  input?: unknown;
  details?: unknown;
  content?: Content[];
}): string | undefined {
  const input = record(event.input);
  if (event.toolName === "bash") {
    const command = input?.command;
    return typeof command === "string" ? command : undefined;
  }
  const details = record(event.details);
  if (typeof details?.then_run === "string" && details.then_run.trim()) {
    return details.then_run.trim();
  }
  const thenRun = record(input?.then_run);
  if (typeof thenRun?.command === "string") return thenRun.command;
  if (typeof input?.then_run === "string") return input.then_run;
  const text = textOf(event.content);
  const marker = text.match(/\[then_run(?::(?:succeeded|failed))?]\s+([^\n]+)/);
  return marker?.[1]?.trim();
}

export function thenRunBody(text: string): string {
  const idx = text.search(/\[then_run(?::(?:succeeded|failed))?]/);
  if (idx < 0) return text;
  const nl = text.indexOf("\n", idx);
  return nl >= 0 ? text.slice(nl + 1) : "";
}

export function scoutLines(body: string, max = MAX_SCOUT_LINES): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of body.split(/\r?\n/)) {
    const line = raw.trimEnd();
    if (line.length < 8 || line.length > MAX_QUOTE) continue;
    if (!FAILURE_SIGNAL.test(line)) continue;
    if (seen.has(line)) continue;
    seen.add(line);
    out.push(line);
    if (out.length >= max) break;
  }
  return out;
}

export function clipForLlm(body: string, scout: string[]): string {
  if (body.length <= CLIP_HEAD + CLIP_TAIL) return body;
  const head = body.slice(0, CLIP_HEAD);
  const tail = body.slice(-CLIP_TAIL);
  const extra = scout.filter((line) => !head.includes(line) && !tail.includes(line));
  return [head, extra.length ? extra.join("\n") : "", tail]
    .filter(Boolean)
    .join("\n…\n");
}

export function quotesVerified(quotes: string[], body: string): boolean {
  return (
    quotes.length > 0 &&
    quotes.length <= MAX_SCOUT_LINES &&
    quotes.every(
      (quote) =>
        quote.length >= 1 &&
        quote.length <= MAX_QUOTE &&
        body.includes(quote),
    )
  );
}

function receiptText(opts: {
  command: string;
  hash: string;
  bytes: number;
  lines: number;
  path: string;
  isError: boolean;
  quotes: string[];
  via: string;
}): string {
  const status = opts.isError ? "failure" : "success";
  const lines = [
    "advait_epr_v1",
    `status=${status}`,
    `command_sha256=${sha256(opts.command)}`,
    `source_sha256=${opts.hash}`,
    `source_bytes=${opts.bytes}`,
    `source_lines=${opts.lines}`,
    `source_artifact=${opts.path}`,
    `reducer=${opts.via}`,
    "verified_evidence:",
  ];
  for (const quote of opts.quotes) {
    lines.push(`- quote=${JSON.stringify(quote)}`);
  }
  lines.push(
    "readback=read the source_artifact (or bash sed -n) for exact context",
  );
  return lines.join("\n");
}

function extractJsonObject(raw: string): unknown {
  const trimmed = raw.trim();
  const start = trimmed.indexOf("{");
  const end = trimmed.lastIndexOf("}");
  if (start < 0 || end <= start) throw new Error("no-json");
  return JSON.parse(trimmed.slice(start, end + 1));
}

async function callCompactor(
  clipped: string,
  isError: boolean,
  hash: string,
  signal: AbortSignal | undefined,
): Promise<string[] | undefined> {
  const payload = {
    model: "compactor",
    temperature: 0,
    max_tokens: 512,
    messages: [
      {
        role: "system",
        content:
          "You are a lossless test/build output reducer. Return one JSON object only. " +
          "evidence quotes must be exact contiguous substrings from the log. " +
          `status must be ${isError ? "failure" : "success"}. At most ${MAX_SCOUT_LINES} evidence items. ` +
          '{"schema":"advait-epr/1","source_sha256":string,"status":"success"|"failure","uncertain":boolean,' +
          '"evidence":[{"kind":"fatal"|"failure"|"warning"|"target"|"summary","quote":string}]}',
      },
      {
        role: "user",
        content: `source_sha256=${hash}\nis_error=${isError}\n<untrusted_log>\n${clipped}\n</untrusted_log>`,
      },
    ],
  };
  const body = JSON.stringify(payload);
  for (const url of COMPACT_URLS) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), LLM_TIMEOUT_MS);
    const relay = () => controller.abort();
    signal?.addEventListener("abort", relay, { once: true });
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body,
        signal: controller.signal,
      });
      if (!response.ok) continue;
      const data = (await response.json()) as {
        choices?: Array<{ message?: { content?: string } }>;
      };
      const raw = data.choices?.[0]?.message?.content;
      if (!raw) continue;
      const parsed = extractJsonObject(raw) as {
        evidence?: Array<{ quote?: unknown }>;
      };
      const quotes = (parsed.evidence ?? [])
        .map((item) => item.quote)
        .filter((quote): quote is string => typeof quote === "string");
      if (quotes.length) return quotes;
    } catch {
      continue;
    } finally {
      clearTimeout(timer);
      signal?.removeEventListener("abort", relay);
    }
  }
  return undefined;
}

async function archiveBody(
  sessionId: string,
  toolCallId: string,
  body: string,
): Promise<{ path: string; hash: string; bytes: number; lines: number }> {
  const dir = join(getAgentDir(), "epr", sessionId);
  await mkdir(dir, { recursive: true });
  const hash = sha256(body);
  const path = join(dir, `${toolCallId}-${hash.slice(0, 12)}.log`);
  await writeFile(path, body, "utf8");
  return {
    path,
    hash,
    bytes: Buffer.byteLength(body, "utf8"),
    lines: body.split(/\r?\n/).length,
  };
}

function sessionIdOf(ctx: ExtensionContext): string {
  const manager = ctx.sessionManager as {
    getSessionId?: () => string | undefined;
    getSessionFile?: () => string | undefined;
  };
  return manager.getSessionId?.() || manager.getSessionFile?.() || "ephemeral";
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_result", async (event, ctx) => {
    try {
      const command = commandOf(event);
      if (!command || !DIAGNOSTIC_COMMAND.test(command)) return;
      const fullText = textOf(event.content);
      const body =
        event.toolName === "bash" ? fullText : thenRunBody(fullText) || fullText;
      if (Buffer.byteLength(body, "utf8") < MIN_BYTES) return;
      if (LIKELY_SECRET.test(body)) return;

      const fusedFailed = /\[then_run:failed]/.test(fullText);
      const isError = Boolean(event.isError) || fusedFailed;
      const archived = await archiveBody(
        sessionIdOf(ctx).replace(/[/\\]/g, "_"),
        event.toolCallId || "tool",
        body,
      );

      let via = "scout";
      let quotes = scoutLines(body);
      const noisy = quotes.length >= MAX_SCOUT_LINES;
      const needLlm = (isError && quotes.length === 0) || noisy;
      if (needLlm) {
        const llmQuotes = await callCompactor(
          clipForLlm(body, scoutLines(body, 40)),
          isError,
          archived.hash,
          ctx.signal,
        );
        if (llmQuotes) {
          quotes = llmQuotes;
          via = "compact/compactor";
        }
      }

      let receipt: string | undefined;
      if (quotesVerified(quotes, body)) {
        receipt = receiptText({
          command,
          hash: archived.hash,
          bytes: archived.bytes,
          lines: archived.lines,
          path: archived.path,
          isError,
          quotes,
          via,
        });
      } else if (!isError && quotes.length === 0) {
        via = "preview";
        receipt = [
          "advait_epr_v1",
          "status=success",
          `source_sha256=${archived.hash}`,
          `source_bytes=${archived.bytes}`,
          `source_artifact=${archived.path}`,
          `reducer=${via}`,
          "preview_head:",
          body.slice(0, PREVIEW_HEAD),
          "preview_tail:",
          body.slice(-PREVIEW_TAIL),
          "readback=read the source_artifact for the full log",
        ].join("\n");
      } else {
        return;
      }
      if (Buffer.byteLength(receipt, "utf8") >= archived.bytes) return;

      const prefix =
        event.toolName === "bash"
          ? receipt
          : `${fullText.slice(0, fullText.length - body.length)}${receipt}`;
      return {
        content: [{ type: "text", text: prefix }],
        details: {
          ...(record(event.details) ?? {}),
          epr: {
            via,
            sourceSha256: archived.hash,
            sourceBytes: archived.bytes,
            sourcePath: archived.path,
            evidenceCount: quotes.length,
          },
        },
      };
    } catch {
      return;
    }
  });
}
