# Qwen3.8-27B helper on the desktop 6700 XT.
# Import only from hosts/nixos/default.nix (the PC), not odie/garfield.
#
# After switch:
#   qwen38-download default   # Unsloth Dynamic V3 UD-IQ2_S (~8.4 GB, ~128K ctx)
#   qwen38-download q2        # Unsloth UD-Q2_K_XL (~9.8–10.7 GB, quality A/B)
#   qwen38-download unc       # 0bserverx Heretic Q2+MTP (~11.2 GB)
#   # flip active weights (one at a time — 12 GB VRAM):
#   #   QWEN38_VARIANT=default|q2|unc  then: systemctl --user restart qwen38-server
#   curl -s http://127.0.0.1:8080/v1/models
{ pkgs, user, ... }:

let
  llama-cpp-vulkan = import ./llama-cpp-vulkan.nix { inherit pkgs; };
  qwen38-tools = import ./qwen38-tools.nix { inherit pkgs llama-cpp-vulkan; };
  grokQwen38 = import ../shared/grok-local-model.nix {
    id = "qwen38";
    apiModel = "qwen38";
    displayName = "Qwen3.8 27B (RX 6700 XT)";
    description = "Local Qwen3.8-27B helper via llama.cpp Vulkan on :8080";
    contextWindow = 131072;
    maxTokens = 8192;
  };
in
{
  environment.etc."grok/managed_config.toml".text = grokQwen38;

  environment.systemPackages = [
    llama-cpp-vulkan
    qwen38-tools.download
    qwen38-tools.server
  ];

  # Keep the user bus up so the laptop can hit :8080 without a local login.
  users.users.${user}.linger = true;

  systemd.user.services.qwen38-server = {
    description = "Qwen3.8-27B llama-server (Vulkan, RX 6700 XT)";
    wantedBy = [ "default.target" ];
    after = [ "network.target" ];
    path = [ llama-cpp-vulkan ];
    environment = {
      VK_DRIVER_FILES = "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json";
      LD_LIBRARY_PATH = "/run/opengl-driver/lib";
      QWEN38_DEVICE = "Vulkan1";
      # default = V3 IQ2_S (128K helper); q2 = UD-Q2_K_XL; unc = Heretic+MTP.
      QWEN38_VARIANT = "default";
      QWEN38_CONTEXT = "131072";
      # q4_0 KV ≈ 2.1 GB at 128K next to ~8.4 GB weights — fits 12 GB.
      QWEN38_CACHE_TYPE = "q4_0";
      QWEN38_UBATCH = "1024";
      QWEN38_CACHE_REUSE = "256";
      # IQ2_S has no MTP tensors in Dynamic V3; leave unset to auto-disable.
    };
    serviceConfig = {
      ExecStart = "${qwen38-tools.server}/bin/qwen38-server";
      Restart = "on-failure";
      RestartSec = 8;
    };
  };
}
