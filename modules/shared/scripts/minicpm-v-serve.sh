#!/usr/bin/env bash
# MiniCPM-V 4.5 on llama.cpp Vulkan — R9700 only (not iGPU compact, not hipfire).
# Loopback :8093. Unload hipfire before starting (one GPU client).
set -euo pipefail

DIR="${MINICPM_V_DIR:-${HOME}/.local/share/minicpm-v-4.5}"
GGUF="${MINICPM_V_GGUF:-${DIR}/MiniCPM-V-4_5-Q5_K_M.gguf}"
MMPROJ="${MINICPM_V_MMPROJ:-${DIR}/mmproj-model-f16.gguf}"
HOST="${MINICPM_V_HOST:-127.0.0.1}"
PORT="${MINICPM_V_PORT:-8093}"
CTX="${MINICPM_V_CTX:-8192}"
ALIAS="${MINICPM_V_ALIAS:-minicpm-v-4.5}"
# With GGML_VK_VISIBLE_DEVICES=1 the R9700 is the only device → Vulkan0.
DEVICE="${MINICPM_V_DEVICE:-Vulkan0}"

if [[ ! -f "$GGUF" ]]; then
  echo "minicpm-v-serve: missing $GGUF (run minicpm-v-fetch.sh)" >&2
  exit 127
fi
if [[ ! -f "$MMPROJ" ]]; then
  echo "minicpm-v-serve: missing $MMPROJ" >&2
  exit 127
fi

LLAMA="${MINICPM_V_LLAMA_SERVER:-${COMPACT_LLAMA_SERVER:-}}"
if [[ -z "$LLAMA" ]]; then
  if command -v llama-server >/dev/null 2>&1; then
    LLAMA="$(command -v llama-server)"
  else
    LLAMA="$(ls -1 /nix/store/*-llama-cpp-vulkan-*/bin/llama-server 2>/dev/null | tail -1 || true)"
  fi
fi
if [[ -z "${LLAMA}" || ! -x "$LLAMA" ]]; then
  echo "minicpm-v-serve: llama-server (vulkan) not found" >&2
  exit 127
fi

# Do not inherit hipfire HIP (R9700 occupied) and do not steal iGPU compact.
unset HIP_VISIBLE_DEVICES ROCR_VISIBLE_DEVICES HIP_PATH HIP_PLATFORM
export GGML_VK_VISIBLE_DEVICES="${GGML_VK_VISIBLE_DEVICES:-1}"

exec "$LLAMA" \
  --model "$GGUF" \
  --mmproj "$MMPROJ" \
  --alias "$ALIAS" \
  --host "$HOST" \
  --port "$PORT" \
  --ctx-size "$CTX" \
  --device "$DEVICE" \
  -ngl 99 \
  --parallel 1 \
  --reasoning off \
  --jinja \
  --no-webui
