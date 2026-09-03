# MTP-torch — ROCm PyTorch venv for MTP-head training (scripts/mtp_train/).
#
# Lazy bootstrap (mirrors mlx-mac.nix): nothing downloads at switch time.
# First `mtp-torch` run creates $HOME/.local/share/mtp-torch/venv
# (python3.11) and pip-installs torch (ROCm 7.x index, matches system
# HIP 7.2) + transformers + datasets. Reinstalls when requirements change
# (stamp file). Re-run `mtp-torch <script> [args]` to train.
#
# Notes:
# - nix-ld (modules/nixos/common.nix) must stay enabled: pip torch wheels
#   ship bundled .so files needing system loader paths.
# - If torch-rocm lacks a gfx1201 target, training still works via
#   HSA_OVERRIDE_GFX_VERSION=11.0.0 (correctness spot-check required).
#   Recent torch 2.11+ rocm7.x wheels include gfx120x.
# - Linux/R9700 only: import from modules/nixos/home-manager.nix, NOT
#   shared (pip torch-rocm does not install on darwin).
{ pkgs, lib, ... }:

let
  venvDir = "$HOME/.local/share/mtp-torch/venv";
  # pip torch wheels link system libstdc++/zlib, not the nix store.
  # writeShellApplication does not propagate these; export explicitly
  # (same pattern as headroom.nix).
  libPath = lib.makeLibraryPath [
    pkgs.stdenv.cc.cc
    pkgs.zlib
    pkgs.zstd
    pkgs.openssl
  ];
  mtpTorchRequirements = pkgs.writeText "mtp-torch-requirements.txt" ''
    --extra-index-url https://download.pytorch.org/whl/rocm7.2
    torch
    transformers
    datasets
    safetensors
    accelerate
  '';
  mtpTorch = pkgs.writeShellApplication {
    name = "mtp-torch";
    runtimeInputs = [
      pkgs.python311
      pkgs.python311Packages.virtualenv
    ];
    text = ''
      set -euo pipefail
      export LD_LIBRARY_PATH="${libPath}:''${LD_LIBRARY_PATH:-}"
      venv="${venvDir}"
      stamp="$venv/.requirements"
      requirements="${mtpTorchRequirements}"
      if [[ ! -x "$venv/bin/python" ]] || [[ ! -f "$stamp" ]] || ! cmp -s "$stamp" "$requirements"; then
        echo "mtp-torch: (re)building venv at $venv (multi-GB torch download)..." >&2
        rm -rf "$venv"
        mkdir -p "$(dirname "$venv")"
        virtualenv -p "${pkgs.python311}/bin/python3.11" "$venv"
        "$venv/bin/python" -m pip install --upgrade pip setuptools wheel
        "$venv/bin/python" -m pip install --no-cache-dir -r "$requirements"
        cp "$requirements" "$stamp"
      fi
      export HF_HOME="$HOME/.cache/huggingface"
      export XDG_CACHE_HOME="$HOME/.cache"
      exec "$venv/bin/python" "$@"
    '';
  };
in
{
  home.packages = [ mtpTorch ];
  home.sessionVariables = {
    MTP_TORCH_VENV = "$HOME/.local/share/mtp-torch/venv";
  };
}
