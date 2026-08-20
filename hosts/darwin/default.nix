{ config, pkgs, llm-agents-nix, ... }:
let 
  user = "amitsheokand";
  agents = llm-agents-nix.packages.${pkgs.stdenv.hostPlatform.system};
  grokQwen35 = import ../../modules/shared/grok-local-model.nix {
    id = "qwen35";
    apiModel = "/Users/${user}/models/DeepSeek-V4-Pro-Qwen3.5-9B-4bit";
    displayName = "Qwen3.5 9B (MLX)";
    description = "Local DeepSeek-V4-Pro-Qwen3.5 9B 4-bit via mlx-vlm on :8080";
    contextWindow = 65536;
    maxTokens = 4096;
  };
  mlxLmRequirements = pkgs.writeText "mlx-lm-requirements.txt" ''
    mlx-lm
    mlx-vlm
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

      max_tokens="''${MLX_LM_MAX_TOKENS:-4096}"
      # Match mlx-lm's default. 128 makes long prompts needlessly granular.
      # Override with MLX_LM_PREFILL_STEP_SIZE when benchmarking.
      prefill_step_size="''${MLX_LM_PREFILL_STEP_SIZE:-2048}"
      max_num_seqs="''${MLX_LM_MAX_NUM_SEQS:-1}"
      # Reserve enough KV-cache space for the 64K orchestration context.
      # Lower this per session with MLX_LM_MAX_KV_SIZE when memory is tight.
      max_kv_size="''${MLX_LM_MAX_KV_SIZE:-65536}"
      model_path="''${MLX_LM_MODEL:-$HOME/models/DeepSeek-V4-Pro-Qwen3.5-9B-4bit}"

      exec "$venv/bin/python" -m mlx_vlm.server \
        --host 127.0.0.1 \
        --port 8080 \
        --model "$model_path" \
        --max-tokens "$max_tokens" \
        --prefill-step-size "$prefill_step_size" \
        --max-num-seqs "$max_num_seqs" \
        --max-kv-size "$max_kv_size"
    '';
  };
in
{
  imports = [
    ../../modules/darwin/home-manager.nix
    ../../modules/shared
  ];

  nix = {
    enable = false;
    package = pkgs.nix;
    settings = {
      trusted-users = [ "@admin" "${user}" ];
      substituters = [
        "https://nix-community.cachix.org"
        "https://cache.nixos.org"
        "https://cache.numtide.com"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      ];
    };
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  environment.systemPackages =
    (import ../../modules/darwin/packages.nix { inherit pkgs; })
    ++ [
      agents.claude-code
      agents.codex
      agents.grok
      agents.pi
      agents.prime-agent
    ];

  # Grok /model picker: keep cloud grok-* and add local Qwen3.5.
  environment.etc."grok/managed_config.toml".text = grokQwen35;

  # MLX model host: expose the DeepSeek/Qwen3.5 9B 4-bit checkpoint through
  # Apple's Metal-backed MLX VLM runtime as an OpenAI-compatible local server.
  launchd.user.agents.mlx-lm-server = {
    command = "${mlxLmServer}/bin/mlx-lm-server";
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/tmp/mlx-lm_${user}.out.log";
      StandardErrorPath = "/tmp/mlx-lm_${user}.err.log";
    };
  };

  system = {
    # Turn off NIX_PATH warnings now that we're using flakes
    checks.verifyNixPath = false;
    primaryUser = user;
    stateVersion = 4;
    defaults = {
      LaunchServices = {
        LSQuarantine = false;
      };
      NSGlobalDomain = {
        AppleShowAllExtensions = true;
        ApplePressAndHoldEnabled = false;

        # 120, 90, 60, 30, 12, 6, 2
        KeyRepeat = 2;

        # 120, 94, 68, 35, 25, 15
        InitialKeyRepeat = 15;
        "com.apple.mouse.tapBehavior" = 1;
        "com.apple.sound.beep.volume" = 0.0;
        "com.apple.sound.beep.feedback" = 0;
      };
      dock = {
        autohide = false;
        show-recents = false;
        launchanim = true;
        mouse-over-hilite-stack = true;
        orientation = "left";
        tilesize = 48;
      };
      finder = {
        _FXShowPosixPathInTitle = false;
      };
      trackpad = {
        Clicking = true;
        TrackpadThreeFingerDrag = true;
      };
    };
    keyboard = {
      enableKeyMapping = true;
    };
  };

  networking.hostName = "ai-mac";
}
