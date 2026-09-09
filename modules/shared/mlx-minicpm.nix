# Mac MLX MiniCPM5-2B — login-resident long-context lane on :8080.
#
# 2.5B / 128k native context. Fits with Compactor on :8081 on 24 GB M4.
# Gemma 12B stays on-demand (`mlx-lane gemma`) and exclusive with this lane
# (same port). Bind 0.0.0.0 so Pi on nixos/vaayu can use
# http://ai-mac.local:8080/v1. mlx-lm rejects unknown ids — alias `longctx`
# and `minicpm` to the filesystem path.
{ user, pkgs }:

let
  mlxMac = import ./mlx-mac.nix { inherit user pkgs; };
  modelPath = "/Users/${user}/models/MiniCPM5-2B-MLX-4bit";
  listenPort = 8080;
  contextWindow = 65536;
  maxTokens = 8192;
  promptCacheBytes = 2000000000;
  grokLocal = import ./grok-local-model.nix {
    id = "longctx";
    apiModel = "longctx";
    displayName = "MiniCPM5-2B (MLX longctx)";
    description = "Local MiniCPM5-2B 4-bit via mlx-lm on :8080 — 64k advertised / 128k native";
    inherit contextWindow maxTokens;
    baseUrl = "http://127.0.0.1:${toString listenPort}/v1";
  };
  mlxMinicpmServe = pkgs.writeText "mlx-minicpm-serve.py" ''
import sys
import mlx_lm.server as s

_orig = s.ModelProvider.__init__

def _init(self, cli_args, *args, **kwargs):
    _orig(self, cli_args, *args, **kwargs)
    for alias in ("longctx", "minicpm"):
        self._model_map[alias] = cli_args.model
        self._adapter_map[alias] = getattr(cli_args, "adapter_path", None)
        self._draft_model_map[alias] = None

s.ModelProvider.__init__ = _init
sys.argv[0] = "mlx_lm.server"
s.main()
  '';
  mlxLmMinicpmServer = pkgs.writeShellApplication {
    name = "mlx-lm-minicpm";
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
      model_path="${modelPath}"

      if [[ ! -x "$venv/bin/python" ]] || [[ ! -f "$stamp" ]] || ! cmp -s "$stamp" "$requirements"; then
        rm -rf "$venv"
        mkdir -p "$HOME/.local/share/mlx-lm"
        virtualenv -p "${pkgs.python311}/bin/python3.11" "$venv"
        "$venv/bin/python" -m pip install --upgrade pip setuptools wheel
        "$venv/bin/python" -m pip install --no-cache-dir -r "$requirements"
        cp "$requirements" "$stamp"
      fi

      if [[ ! -f "$model_path/config.json" ]]; then
        echo "MiniCPM MLX weights missing at $model_path" >&2
        exit 1
      fi

      chat_template_args="''${MLX_LM_MINICPM_CHAT_TEMPLATE_ARGS:-{\"enable_thinking\":false}}"
      max_tokens="''${MLX_LM_MINICPM_MAX_TOKENS:-${toString maxTokens}}"
      prompt_cache_bytes="''${MLX_LM_MINICPM_PROMPT_CACHE_BYTES:-${toString promptCacheBytes}}"

      exec "$venv/bin/python" ${mlxMinicpmServe} \
        --host 0.0.0.0 \
        --port ${toString listenPort} \
        --model "$model_path" \
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
    modelPath
    listenPort
    contextWindow
    maxTokens
    grokLocal
    mlxLmMinicpmServer
    ;
}
