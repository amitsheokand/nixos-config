{ pkgs, bonsai-llama-vulkan }:

let
  modelRepo = "https://huggingface.co/prism-ml/Ternary-Bonsai-27B-gguf/resolve/main";
  modelFile = "Ternary-Bonsai-27B-Q2_0.gguf";
  visionFile = "Ternary-Bonsai-27B-mmproj-Q8_0.gguf";
  dataDir = "\${XDG_DATA_HOME:-$HOME/.local/share}/bonsai/models/ternary-27b";
in
{
  download = pkgs.writeShellApplication {
    name = "bonsai-download";
    runtimeInputs = [ pkgs.aria2 ];
    text = ''
      model_dir="''${BONSAI_MODEL_DIR:-${dataDir}}"
      mkdir -p "$model_dir"

      aria2c -c -x 16 -s 16 -k 4M --file-allocation=none \
        -d "$model_dir" -o "${modelFile}" "${modelRepo}/${modelFile}"

      if [[ "''${1:-}" == "--vision" ]]; then
        aria2c -c -x 16 -s 16 -k 4M --file-allocation=none \
          -d "$model_dir" -o "${visionFile}" "${modelRepo}/${visionFile}"
      fi
    '';
  };

  server = pkgs.writeShellApplication {
    name = "bonsai-server";
    runtimeInputs = [ bonsai-llama-vulkan ];
    text = ''
      model_dir="''${BONSAI_MODEL_DIR:-${dataDir}}"
      model="$model_dir/${modelFile}"
      vision="$model_dir/${visionFile}"

      if [[ ! -s "$model" || -e "$model.aria2" ]]; then
        echo "Bonsai model is missing or incomplete: $model" >&2
        echo "Download it with: bonsai-download" >&2
        exit 1
      fi

      args=(
        -m "$model"
        --device Vulkan0
        -ngl 99
        -fa on
        -c "''${BONSAI_CONTEXT:-40960}"
        -np 1
        --host "''${BONSAI_HOST:-127.0.0.1}"
        --port "''${BONSAI_PORT:-8080}"
        --temp 0.7
        --top-p 0.95
        --top-k 20
        --min-p 0
        --jinja
        --reasoning-budget "''${BONSAI_REASONING_BUDGET:--1}"
      )

      if [[ "''${BONSAI_VISION:-0}" == "1" && -s "$vision" ]]; then
        args+=(--mmproj "$vision" --image-max-tokens "''${BONSAI_IMAGE_MAX_TOKENS:-1024}")
      fi

      exec llama-server "''${args[@]}" "$@"
    '';
  };

  bench = pkgs.writeShellApplication {
    name = "bonsai-bench";
    runtimeInputs = [ bonsai-llama-vulkan ];
    text = ''
      model_dir="''${BONSAI_MODEL_DIR:-${dataDir}}"
      model="$model_dir/${modelFile}"

      if [[ ! -s "$model" || -e "$model.aria2" ]]; then
        echo "Bonsai model is missing or incomplete: $model" >&2
        exit 1
      fi

      exec llama-bench -m "$model" --device Vulkan0 -ngl 99 -p 512 -n 128 -r 3 "$@"
    '';
  };
}
