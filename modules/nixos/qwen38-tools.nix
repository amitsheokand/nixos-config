{ pkgs, llama-cpp-vulkan }:

let
  dataDir = "\${XDG_DATA_HOME:-$HOME/.local/share}/qwen38";

  # Helper on 12 GB: Dynamic V3 IQ2_S frees KV for ~128K. Keep Q2_K_XL + unc
  # as optional A/B. Switch with QWEN38_VARIANT=... or: qwen38-download <variant>
  variants = {
    default = {
      repo = "https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main";
      file = "Qwen3.8-27B-UD-IQ2_S.gguf";
    };
    q2 = {
      repo = "https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main";
      file = "Qwen3.8-27B-UD-Q2_K_XL.gguf";
    };
    unc = {
      repo = "https://huggingface.co/0bserverx/Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF/resolve/main";
      file = "RVN-Q2_K-mtp.gguf";
    };
  };
in
{
  download = pkgs.writeShellApplication {
    name = "qwen38-download";
    runtimeInputs = [ pkgs.aria2 ];
    text = ''
      variant="''${1:-''${QWEN38_VARIANT:-default}}"
      model_dir="''${QWEN38_MODEL_DIR:-${dataDir}}"
      mkdir -p "$model_dir"

      case "$variant" in
        default|iq2)
          repo="${variants.default.repo}"
          file="${variants.default.file}"
          ;;
        q2|q2xl)
          repo="${variants.q2.repo}"
          file="${variants.q2.file}"
          ;;
        unc|uncensored)
          repo="${variants.unc.repo}"
          file="${variants.unc.file}"
          ;;
        *)
          echo "usage: qwen38-download [default|iq2|q2|unc]" >&2
          exit 1
          ;;
      esac

      echo "Downloading $variant → $model_dir/$file"
      aria2c -c -x 16 -s 16 -k 4M --file-allocation=none \
        -d "$model_dir" -o "$file" "$repo/$file"
    '';
  };

  server = pkgs.writeShellApplication {
    name = "qwen38-server";
    runtimeInputs = [ llama-cpp-vulkan ];
    text = ''
      variant="''${QWEN38_VARIANT:-default}"
      model_dir="''${QWEN38_MODEL_DIR:-${dataDir}}"

      case "$variant" in
        default|iq2) file="${variants.default.file}" ;;
        q2|q2xl) file="${variants.q2.file}" ;;
        unc|uncensored) file="${variants.unc.file}" ;;
        *)
          echo "QWEN38_VARIANT must be default|iq2|q2|unc (got: $variant)" >&2
          exit 1
          ;;
      esac

      model="$model_dir/$file"
      if [[ ! -s "$model" || -e "$model.aria2" ]]; then
        echo "Qwen3.8 model is missing or incomplete: $model" >&2
        echo "Download it with: qwen38-download $variant" >&2
        exit 1
      fi

      # NixOS Vulkan ICDs live here; a user unit does not inherit a GUI session.
      export VK_DRIVER_FILES="''${VK_DRIVER_FILES:-/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json}"
      export LD_LIBRARY_PATH="/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

      # On this desktop Vulkan0 is the Raphael iGPU; Vulkan1 is the 6700 XT.
      device="''${QWEN38_DEVICE:-Vulkan1}"
      # IQ2 leaves more VRAM for KV; unc Q2+MTP is tightest.
      reserve="''${QWEN38_VRAM_RESERVE:-}"
      if [[ -z "$reserve" ]]; then
        case "$variant" in
          unc|uncensored) reserve=256 ;;
          q2|q2xl) reserve=512 ;;
          *) reserve=384 ;;
        esac
      fi

      # Dynamic V3 strips MTP from ≤ UD-IQ2_S (~8.37 GB); only enable on q2/unc.
      mtp="''${QWEN38_MTP:-}"
      if [[ -z "$mtp" ]]; then
        case "$variant" in
          q2|q2xl|unc|uncensored) mtp=1 ;;
          *) mtp=0 ;;
        esac
      fi

      args=(
        -m "$model"
        -a "''${QWEN38_ALIAS:-qwen38}"
        --device "$device"
        -ngl 99
        -fa on
        -fit on
        -fitt "$reserve"
        -c "''${QWEN38_CONTEXT:-131072}"
        -np 1
        -ub "''${QWEN38_UBATCH:-1024}"
        --cache-type-k "''${QWEN38_CACHE_TYPE:-q4_0}"
        --cache-type-v "''${QWEN38_CACHE_TYPE:-q4_0}"
        --cache-reuse "''${QWEN38_CACHE_REUSE:-256}"
        --host "''${QWEN38_HOST:-0.0.0.0}"
        --port "''${QWEN38_PORT:-8080}"
        --jinja
        --reasoning off
        --temp 0.6
        --top-p 0.95
        --top-k 20
        --min-p 0
      )

      if [[ "$mtp" == "1" ]]; then
        args+=(--spec-type draft-mtp --spec-draft-n-max 2)
      fi

      echo "qwen38-server: variant=$variant file=$file device=$device ctx=''${QWEN38_CONTEXT:-131072} mtp=$mtp" >&2
      exec llama-server "''${args[@]}" "$@"
    '';
  };
}
