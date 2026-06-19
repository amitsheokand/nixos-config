{ pkgs }:

with pkgs;
let shared-packages = import ../shared/packages.nix { inherit pkgs; }; in
shared-packages ++ [
  # F
  fswatch # File change monitor

  # Development Tools
  code-cursor # Official Cursor IDE package from nixpkgs

  # === Local LLM ===
  ollama  # On NixOS this comes from services.ollama.enable
]
