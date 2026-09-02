#!/usr/bin/env bash
# Qwen3.5-0.8B compact fallback. iGPU Vulkan0 only — never R9700 / hipfire.
set -euo pipefail

GGUF="${COMPACT_TINY_GGUF:-${HOME}/.local/share/pi-compact/Qwen3.5-0.8B-Q8_0.gguf}"
HOST="${COMPACT_TINY_HOST:-127.0.0.1}"
PORT="${COMPACT_TINY_PORT:-8092}"
CTX="${COMPACT_TINY_CTX:-32768}"
ALIAS="${COMPACT_TINY_ALIAS:-qwen3.5-0.8b}"
DEVICE="${COMPACT_TINY_DEVICE:-Vulkan0}"

if [[ ! -f "$GGUF" ]]; then
  echo "pi-compact-tiny: missing $GGUF" >&2
  exit 127
fi

LLAMA="${COMPACT_LLAMA_SERVER:-}"
if [[ -z "$LLAMA" ]]; then
  if command -v llama-server >/dev/null 2>&1; then
    LLAMA="$(command -v llama-server)"
  else
    LLAMA="$(ls -1 /nix/store/*-llama-cpp-vulkan-*/bin/llama-server 2>/dev/null | tail -1 || true)"
  fi
fi
if [[ -z "${LLAMA}" || ! -x "$LLAMA" ]]; then
  echo "pi-compact-tiny: llama-server not found" >&2
  exit 127
fi

# Do not inherit hipfire's HIP_VISIBLE_DEVICES=0 (R9700).
unset HIP_VISIBLE_DEVICES ROCR_VISIBLE_DEVICES HIP_PATH
export GGML_VK_VISIBLE_DEVICES="${GGML_VK_VISIBLE_DEVICES:-0}"

exec "$LLAMA" \
  --model "$GGUF" \
  --alias "$ALIAS" \
  --host "$HOST" \
  --port "$PORT" \
  --ctx-size "$CTX" \
  --device "$DEVICE" \
  -ngl 99 \
  --parallel 1 \
  --reasoning off \
  --jinja \
  --chat-template-kwargs '{"enable_thinking":false}'
