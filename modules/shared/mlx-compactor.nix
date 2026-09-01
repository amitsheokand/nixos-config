# Mac MLX Compactor — second server on :8081 so Gemma on :8080 stays loaded.
#
# Weights: Lazarus-Ai/ReAligned-Qwen3.5-4B + LoRA schneewolflabs/Compactor-Qwen3.5-4B,
# fused to ~/models/Compactor-Qwen3.5-4B-4bit. Thinking off. 16k window.
# LAN: 0.0.0.0:8081 for Pi on nixos/odie/vaayu (http://ai-mac.local:8081/v1).
{ user, pkgs }:

let
  mlxMac = import ./mlx-mac.nix { inherit user pkgs; };
  adapterRepo = "schneewolflabs/Compactor-Qwen3.5-4B";
  baseHfRepo = "Lazarus-Ai/ReAligned-Qwen3.5-4B";
  adapterPath = "/Users/${user}/models/Compactor-Qwen3.5-4B-adapter";
  baseMlxPath = "/Users/${user}/models/ReAligned-Qwen3.5-4B-4bit";
  baseHfPath = "/Users/${user}/models/ReAligned-Qwen3.5-4B-hf";
  mergedHfPath = "/Users/${user}/models/Compactor-Qwen3.5-4B-merged-hf";
  fusedPath = "/Users/${user}/models/Compactor-Qwen3.5-4B-4bit";
  compactPort = 8081;
  contextWindow = 16384;
  maxTokens = 4096;
  promptCacheBytes = 2000000000;
  mlxLmCompactServer = pkgs.writeShellApplication {
    name = "mlx-lm-compact";
    runtimeInputs = [
      pkgs.python311
      pkgs.python311Packages.virtualenv
    ];
    text = ''
      set -euo pipefail
      export HF_HOME="$HOME/.cache/huggingface"
      export XDG_CACHE_HOME="$HOME/.cache"
      venv="$HOME/.local/share/mlx-lm/venv"
      stamp="$venv/.requirements"
      requirements="${mlxMac.mlxLmRequirements}"
      adapter_path="${adapterPath}"
      base_mlx="${baseMlxPath}"
      fused_path="${fusedPath}"

      if [[ ! -x "$venv/bin/python" ]] || [[ ! -f "$stamp" ]] || ! cmp -s "$stamp" "$requirements"; then
        echo "mlx-lm-compact: venv missing or stale; start mlx-lm-server first" >&2
        exit 1
      fi

      site_packages="$("$venv/bin/python" - <<'PY'
import site
paths = site.getsitepackages()
print(paths[0] if paths else site.getusersitepackages())
PY
)"
      cat > "$site_packages/mlx_compact_alias.py" <<'EOF'
import os
if os.environ.get("MLX_COMPACT_MODEL_PATH"):
    try:
        import mlx_lm.server as _s
        _orig = _s.ModelProvider.__init__

        def _init(self, cli_args, *args, **kwargs):
            _orig(self, cli_args, *args, **kwargs)
            self._model_map["compactor"] = cli_args.model
            self._adapter_map["compactor"] = getattr(cli_args, "adapter_path", None)
            self._draft_model_map["compactor"] = None

        _s.ModelProvider.__init__ = _init
    except Exception:
        pass
EOF
      echo import mlx_compact_alias > "$site_packages/mlx_compact_alias.pth"

      if [[ ! -f "$fused_path/config.json" ]]; then
        echo "preparing Compactor MLX weights -> $fused_path" >&2
        "$venv/bin/python" - <<'PY'
import os
import subprocess
import sys
from huggingface_hub import snapshot_download

adapter_repo = "${adapterRepo}"
base_hf = "${baseHfRepo}"
adapter_path = "${adapterPath}"
base_mlx = "${baseMlxPath}"
base_hf_path = "${baseHfPath}"
merged_hf = "${mergedHfPath}"
fused_path = "${fusedPath}"
py = sys.executable

os.makedirs(adapter_path, exist_ok=True)
snapshot_download(repo_id=adapter_repo, local_dir=adapter_path)

def run(args):
    print("+", " ".join(args), flush=True)
    return subprocess.call(args)

if not os.path.isfile(os.path.join(base_mlx, "config.json")):
    os.makedirs(base_mlx, exist_ok=True)
    rc = run([
        py, "-m", "mlx_lm.convert",
        "--hf-path", base_hf,
        "--mlx-path", base_mlx,
        "-q", "--q-bits", "4",
    ])
    if rc != 0:
        print("mlx_lm.convert of base failed", flush=True)

if os.path.isfile(os.path.join(base_mlx, "config.json")):
    rc = run([
        py, "-m", "mlx_lm.fuse",
        "--model", base_mlx,
        "--adapter-path", adapter_path,
        "--save-path", fused_path,
    ])
    if rc == 0 and os.path.isfile(os.path.join(fused_path, "config.json")):
        print("fused LoRA into", fused_path, flush=True)
        raise SystemExit(0)

print("PEFT merge fallback (CPU, one-shot)", flush=True)
run([py, "-m", "pip", "install", "--no-cache-dir", "peft", "torch"])
os.makedirs(base_hf_path, exist_ok=True)
os.makedirs(merged_hf, exist_ok=True)
snapshot_download(repo_id=base_hf, local_dir=base_hf_path)
import torch
try:
    from transformers import AutoModelForImageTextToText as AutoModel
except Exception:
    from transformers import AutoModelForCausalLM as AutoModel
from peft import PeftModel

model = AutoModel.from_pretrained(base_hf_path, torch_dtype=torch.float32, device_map="cpu")
model = PeftModel.from_pretrained(model, adapter_path)
model = model.merge_and_unload()
model.save_pretrained(merged_hf)
rc = run([
    py, "-m", "mlx_lm.convert",
    "--hf-path", merged_hf,
    "--mlx-path", fused_path,
    "-q", "--q-bits", "4",
])
raise SystemExit(0 if rc == 0 else rc)
PY
      fi

      if [[ ! -f "$fused_path/config.json" ]]; then
        echo "Compactor MLX weights missing at $fused_path" >&2
        exit 1
      fi

      export MLX_COMPACT_MODEL_PATH="$fused_path"
      chat_template_args="''${MLX_LM_COMPACT_CHAT_TEMPLATE_ARGS:-{\"enable_thinking\":false}}"
      max_tokens="''${MLX_LM_COMPACT_MAX_TOKENS:-${toString maxTokens}}"
      prompt_cache_bytes="''${MLX_LM_COMPACT_PROMPT_CACHE_BYTES:-${toString promptCacheBytes}}"

      exec "$venv/bin/python" -m mlx_lm.server \
        --host 0.0.0.0 \
        --port ${toString compactPort} \
        --model "$fused_path" \
        --use-default-chat-template \
        --trust-remote-code \
        --chat-template-args "$chat_template_args" \
        --max-tokens "$max_tokens" \
        --prefill-step-size 2048 \
        --prompt-cache-bytes "$prompt_cache_bytes"
    '';
  };
in
{
  inherit
    fusedPath
    compactPort
    contextWindow
    maxTokens
    mlxLmCompactServer
    ;
}
