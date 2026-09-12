# MiniCPM-V 4.5 — resident R9700 job (llama.cpp Vulkan).
# Not hipfire. Swap GGUF via MINICPM_V_GGUF / MMPROJ, or later a hipfire VL SKU.
# 27B class is parked: start hipfire-serve manually (Conflicts with this unit).
{
  pkgs,
  lib,
  user,
}:

let
  homeDir = "/home/${user}";
  serveSrc = ./scripts/minicpm-v-serve.sh;
  fetchSrc = ./scripts/minicpm-v-fetch.sh;

  serve = pkgs.writeShellApplication {
    name = "minicpm-v-serve";
    runtimeInputs = [ pkgs.coreutils pkgs.bash ];
    text = ''
      exec ${pkgs.bash}/bin/bash ${serveSrc}
    '';
  };

  fetch = pkgs.writeShellApplication {
    name = "minicpm-v-fetch";
    runtimeInputs = [ pkgs.coreutils pkgs.bash ];
    text = ''
      exec ${pkgs.bash}/bin/bash ${fetchSrc}
    '';
  };
in
{
  inherit serve fetch;

  packages = [ serve fetch ];

  sessionVariables = {
    MINICPM_V_BASE_URL = "http://127.0.0.1:8093/v1";
    VL_CAPTURE_ENDPOINT = "http://127.0.0.1:8093/v1";
  };

  systemdUserServices = {
    minicpm-v = {
      Unit = {
        Description = "MiniCPM-V 4.5 (R9700 Vulkan1, not iGPU, not hipfire 27B)";
        After = [ "graphical-session.target" ];
        Conflicts = [ "hipfire-serve.service" "herder-minicpm5.service" ];
      };
      Service = {
        ExecStart = "${serve}/bin/minicpm-v-serve";
        Restart = "on-failure";
        RestartSec = "3";
        Environment = [
          "HOME=${homeDir}"
          "GGML_VK_VISIBLE_DEVICES=1"
        ];
      };
      Install.WantedBy = [ "default.target" ];
    };
  };

  # Drop the ad-hoc MiniCPM5 text herder; hipfire 27B stays installable but not enabled.
  retireScript = ''
    rm -f "$HOME/.config/systemd/user/herder-minicpm5.service"
    rm -f "$HOME/.config/systemd/user/herder-minicpm5-vaayu.service"
    ${pkgs.systemd}/bin/systemctl --user disable --now herder-minicpm5.service 2>/dev/null || true
    ${pkgs.systemd}/bin/systemctl --user disable --now herder-minicpm5-vaayu.service 2>/dev/null || true
    ${pkgs.systemd}/bin/systemctl --user disable --now hipfire-serve.service 2>/dev/null || true
    ${pkgs.systemd}/bin/systemctl --user disable --now hipfire-daemon-watch.service 2>/dev/null || true
    ${pkgs.systemd}/bin/systemctl --user disable --now hipfire-profile-proxy.service 2>/dev/null || true
  '';
}
