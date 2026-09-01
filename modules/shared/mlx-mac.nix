# Mac MLX local model — single source of truth for ai-mac.
#
# Gemma 4 12B coder via mlx-lm. On demand (`mlx-lane gemma`); Compactor is
# the login-resident lane. Weights under ~/models/. Pi/Grok/Codex use the
# filesystem path as the API model id.
{ user, pkgs }:

let
  mlxModelRepo = "mlx-community/gemma-4-12b-coder-fable5-composer2.5-4bit";
  mlxModelPath = "/Users/${user}/models/gemma-4-12b-coder-fable5-composer2.5-4bit";
  mlxPickerName = "gemmacoder";
  contextWindow = 32768;
  maxTokens = 4096;
  serverMaxTokens = 4096;
  prefillStepSize = 2048;
  # 5 GB prompt-cache (was 8 GB; OOM at ~6.6 GB on 24 GB M4).
  promptCacheBytes = 5000000000;
  grokLocal = import ./grok-local-model.nix {
    id = mlxPickerName;
    apiModel = mlxModelPath;
    displayName = "Gemma 4 12B Coder (MLX)";
    description = "Local Gemma 4 12B coder 4-bit (Fable/Composer) via mlx-lm on :8080";
    inherit contextWindow;
    maxTokens = serverMaxTokens;
  };
  mlxLmRequirements = pkgs.writeText "mlx-lm-requirements.txt" ''
    mlx
    mlx-lm @ git+https://github.com/ml-explore/mlx-lm.git
    mlx-optiq
  '';
  mlxLmServer = pkgs.writeShellApplication {
    name = "mlx-lm-server";
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
      requirements="${mlxLmRequirements}"
      model_repo="${mlxModelRepo}"

      if [[ ! -x "$venv/bin/python" ]] || [[ ! -f "$stamp" ]] || ! cmp -s "$stamp" "$requirements"; then
        rm -rf "$venv"
        mkdir -p "$HOME/.local/share/mlx-lm"
        virtualenv -p "${pkgs.python311}/bin/python3.11" "$venv"
        "$venv/bin/python" -m pip install --upgrade pip setuptools wheel
        "$venv/bin/python" -m pip install --no-cache-dir -r "$requirements"
        cp "$requirements" "$stamp"
        site_packages="$("$venv/bin/python" - <<'PY'
import site
paths = site.getsitepackages()
print(paths[0] if paths else site.getusersitepackages())
PY
)"
        cat > "$site_packages/sitecustomize.py" <<'EOF'
try:
    import optiq  # gemma4_unified (12B coder) -> mlx_lm gemma4
except Exception:
    pass
try:
    from transformers import AutoTokenizer

    _orig_register = AutoTokenizer.register

    def _patched_register(cls, config_class, *args, **kwargs):
        if isinstance(config_class, str):
            return None
        return _orig_register(config_class, *args, **kwargs)

    AutoTokenizer.register = classmethod(_patched_register)
except Exception:
    pass
EOF
      fi

      max_tokens="''${MLX_LM_MAX_TOKENS:-${toString serverMaxTokens}}"
      prefill_step_size="''${MLX_LM_PREFILL_STEP_SIZE:-${toString prefillStepSize}}"
      prompt_cache_bytes="''${MLX_LM_PROMPT_CACHE_BYTES:-${toString promptCacheBytes}}"
      model_path="''${MLX_LM_MODEL:-${mlxModelPath}}"

      if [[ ! -f "$model_path/config.json" ]]; then
        echo "pulling $model_repo -> $model_path" >&2
        mkdir -p "$model_path"
        "$venv/bin/python" - <<PY
from huggingface_hub import snapshot_download

snapshot_download(
    repo_id="''${model_repo}",
    local_dir="''${model_path}",
)
PY
      fi

      chat_template_args="''${MLX_LM_CHAT_TEMPLATE_ARGS:-{\"enable_thinking\":true}}"

      exec "$venv/bin/python" -m mlx_lm.server \
        --host 127.0.0.1 \
        --port 8080 \
        --model "$model_path" \
        --use-default-chat-template \
        --trust-remote-code \
        --chat-template-args "$chat_template_args" \
        --max-tokens "$max_tokens" \
        --prefill-step-size "$prefill_step_size" \
        --prompt-cache-bytes "$prompt_cache_bytes"
    '';
  };
in
{
  inherit
    mlxModelRepo
    mlxModelPath
    mlxPickerName
    contextWindow
    maxTokens
    serverMaxTokens
    prefillStepSize
    promptCacheBytes
    grokLocal
    mlxLmRequirements
    mlxLmServer
    ;
}
