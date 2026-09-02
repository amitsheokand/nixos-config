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
  adapterMlxPath = "/Users/${user}/models/Compactor-Qwen3.5-4B-adapter-mlx";
  baseMlxPath = "/Users/${user}/models/ReAligned-Qwen3.5-4B-4bit";
  fusedPath = "/Users/${user}/models/Compactor-Qwen3.5-4B-4bit";
  compactPort = 8081;
  contextWindow = 16384;
  maxTokens = 4096;
  promptCacheBytes = 2000000000;
  # python -m mlx_lm.server reloads the module and drops a .pth monkeypatch.
  mlxCompactServe = pkgs.writeText "mlx-compact-serve.py" ''
import sys
import mlx_lm.server as s

_orig = s.ModelProvider.__init__

def _init(self, cli_args, *args, **kwargs):
    _orig(self, cli_args, *args, **kwargs)
    self._model_map["compactor"] = cli_args.model
    self._adapter_map["compactor"] = getattr(cli_args, "adapter_path", None)
    self._draft_model_map["compactor"] = None

s.ModelProvider.__init__ = _init
sys.argv[0] = "mlx_lm.server"
s.main()
  '';
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
      fused_path="${fusedPath}"

      if [[ ! -x "$venv/bin/python" ]] || [[ ! -f "$stamp" ]] || ! cmp -s "$stamp" "$requirements"; then
        echo "mlx-lm-compact: venv missing or stale; start mlx-lm-server first" >&2
        exit 1
      fi

      if [[ ! -f "$fused_path/config.json" ]]; then
        echo "preparing Compactor MLX weights -> $fused_path" >&2
        "$venv/bin/python" - <<'PY'
import json
import os
import shutil
import subprocess
import sys
from huggingface_hub import snapshot_download
from safetensors.numpy import load_file, save_file

adapter_repo = "${adapterRepo}"
base_hf = "${baseHfRepo}"
adapter_path = "${adapterPath}"
adapter_mlx = "${adapterMlxPath}"
base_mlx = "${baseMlxPath}"
fused_path = "${fusedPath}"
py = sys.executable

os.makedirs(adapter_path, exist_ok=True)
snapshot_download(repo_id=adapter_repo, local_dir=adapter_path)

def run(args):
    print("+", " ".join(args), flush=True)
    return subprocess.call(args)

def peft_to_mlx(src, dst):
    """PEFT adapter_model.safetensors -> mlx-lm adapters.safetensors."""
    with open(os.path.join(src, "adapter_config.json")) as f:
        peft = json.load(f)
    rank = int(peft["r"])
    alpha = float(peft["lora_alpha"])
    os.makedirs(dst, exist_ok=True)
    with open(os.path.join(dst, "adapter_config.json"), "w") as f:
        json.dump({
            "fine_tune_type": "lora",
            "num_layers": 32,
            "lora_parameters": {
                "rank": rank,
                "scale": alpha / rank,
                "dropout": float(peft.get("lora_dropout") or 0),
                "keys": [
                    "self_attn.q_proj",
                    "self_attn.k_proj",
                    "self_attn.v_proj",
                    "self_attn.o_proj",
                    "mlp.gate_proj",
                    "mlp.up_proj",
                    "mlp.down_proj",
                ],
            },
        }, f)
    raw = load_file(os.path.join(src, "adapter_model.safetensors"))
    out = {}
    prefix = "base_model.model.model.language_model.layers."
    for name, tensor in raw.items():
        if not name.startswith(prefix):
            print("skip unexpected adapter key", name, flush=True)
            continue
        rest = name[len(prefix):]
        rest = rest.replace(".lora_A.weight", ".lora_a").replace(".lora_B.weight", ".lora_b")
        mlx_name = "language_model.model.layers." + rest
        out[mlx_name] = tensor.T.copy()
    save_file(out, os.path.join(dst, "adapters.safetensors"))
    print("wrote", len(out), "mlx adapter tensors ->", dst, flush=True)

if not os.path.isfile(os.path.join(base_mlx, "config.json")):
    if os.path.isdir(base_mlx):
        shutil.rmtree(base_mlx)
    rc = run([
        py, "-m", "mlx_lm.convert",
        "--hf-path", base_hf,
        "--mlx-path", base_mlx,
        "-q", "--q-bits", "4",
    ])
    if rc != 0:
        print("mlx_lm.convert of base failed", flush=True)
        raise SystemExit(rc)

peft_to_mlx(adapter_path, adapter_mlx)
if os.path.isdir(fused_path):
    shutil.rmtree(fused_path)
rc = run([
    py, "-m", "mlx_lm.fuse",
    "--model", base_mlx,
    "--adapter-path", adapter_mlx,
    "--save-path", fused_path,
])
if rc == 0 and os.path.isfile(os.path.join(fused_path, "config.json")):
    print("fused LoRA into", fused_path, flush=True)
    raise SystemExit(0)
raise SystemExit(rc if rc != 0 else 1)
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

      exec "$venv/bin/python" ${mlxCompactServe} \
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
