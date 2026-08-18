{ pkgs, llama-cpp-vulkan }:

let
  modelRepo = "https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main";
  modelFile = "Qwen3.8-27B-UD-Q2_K_XL.gguf";
  dataDir = "\${XDG_DATA_HOME:-$HOME/.local/share}/qwen38";
in
{
  download = pkgs.writeShellApplication {
    name = "qwen38-download";
    runtimeInputs = [ pkgs.aria2 ];
    text = ''
      model_dir="''${QWEN38_MODEL_DIR:-${dataDir}}"
      mkdir -p "$model_dir"
      aria2c -c -x 16 -s 16 -k 4M --file-allocation=none \
        -d "$model_dir" -o "${modelFile}" "${modelRepo}/${modelFile}"
    '';
  };

  server = pkgs.writeShellApplication {
    name = "qwen38-server";
    runtimeInputs = [ llama-cpp-vulkan ];
    text = ''
      model_dir="''${QWEN38_MODEL_DIR:-${dataDir}}"
      model="$model_dir/${modelFile}"

      if [[ ! -s "$model" || -e "$model.aria2" ]]; then
        echo "Qwen3.8 model is missing or incomplete: $model" >&2
        echo "Download it with: qwen38-download" >&2
        exit 1
      fi

      # NixOS Vulkan ICDs live here; a user unit does not inherit a GUI session.
      export VK_DRIVER_FILES="''${VK_DRIVER_FILES:-/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json}"
      export LD_LIBRARY_PATH="/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

      # On this desktop Vulkan0 is the Raphael iGPU; Vulkan1 is the 6700 XT.
      device="''${QWEN38_DEVICE:-Vulkan1}"

      args=(
        -m "$model"
        -a qwen38
        --device "$device"
        -ngl 99
        -fa on
        -fit on
        -fitt "''${QWEN38_VRAM_RESERVE:-512}"
        -c "''${QWEN38_CONTEXT:-16384}"
        -np 1
        --cache-type-k q8_0
        --cache-type-v q8_0
        --host "''${QWEN38_HOST:-0.0.0.0}"
        --port "''${QWEN38_PORT:-8080}"
        --jinja
        --reasoning off
        --temp 0.6
        --top-p 0.95
        --top-k 20
        --min-p 0
      )

      if [[ "''${QWEN38_MTP:-1}" == "1" ]]; then
        args+=(--spec-type draft-mtp --spec-draft-n-max 2)
      fi

      exec llama-server "''${args[@]}" "$@"
    '';
  };
}
