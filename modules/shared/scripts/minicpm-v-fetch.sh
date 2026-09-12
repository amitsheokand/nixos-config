#!/usr/bin/env bash
# Fetch MiniCPM-V 4.5 GGUF + mmproj for the Vulkan trial.
# Does not touch hipfire ~/.hipfire/models or defaultBackend.
set -euo pipefail

DEST="${MINICPM_V_DIR:-${HOME}/.local/share/minicpm-v-4.5}"
REPO="${MINICPM_V_REPO:-openbmb/MiniCPM-V-4_5-gguf}"
MODEL="${MINICPM_V_GGUF:-MiniCPM-V-4_5-Q5_K_M.gguf}"
MMPROJ="${MINICPM_V_MMPROJ:-mmproj-model-f16.gguf}"

mkdir -p "$DEST"

if ! command -v hf >/dev/null 2>&1 && ! command -v huggingface-cli >/dev/null 2>&1; then
  echo "minicpm-v-fetch: need hf or huggingface-cli" >&2
  exit 127
fi

HF=(hf download)
if ! command -v hf >/dev/null 2>&1; then
  HF=(huggingface-cli download)
fi

echo "minicpm-v-fetch: $REPO → $DEST" >&2
"${HF[@]}" "$REPO" "$MODEL" "$MMPROJ" --local-dir "$DEST"

test -f "$DEST/$MODEL" || { echo "minicpm-v-fetch: missing $DEST/$MODEL" >&2; exit 1; }
test -f "$DEST/$MMPROJ" || { echo "minicpm-v-fetch: missing $DEST/$MMPROJ" >&2; exit 1; }
echo "minicpm-v-fetch: ok" >&2
