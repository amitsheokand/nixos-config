# Qwen3.8-27B helper on the desktop 6700 XT.
# Import only from hosts/nixos/default.nix (the PC), not odie/garfield.
#
# After switch:
#   qwen38-download
#   systemctl --user restart qwen38-server
#   curl -s http://127.0.0.1:8080/v1/models
{ pkgs, user, ... }:

let
  llama-cpp-vulkan = import ./llama-cpp-vulkan.nix { inherit pkgs; };
  qwen38-tools = import ./qwen38-tools.nix { inherit pkgs llama-cpp-vulkan; };
in
{
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
      QWEN38_CONTEXT = "32768";
      QWEN38_CACHE_TYPE = "q5_0";
      QWEN38_UBATCH = "1024";
      QWEN38_CACHE_REUSE = "256";
    };
    serviceConfig = {
      ExecStart = "${qwen38-tools.server}/bin/qwen38-server";
      Restart = "on-failure";
      RestartSec = 8;
    };
  };
}
