{ config, lib, pkgs, modulesPath, user, inputs, claude-code-nix, codex-cli-nix, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./hardware-configuration.nix

    # Shared cross-platform config (nixpkgs, overlays) + shared NixOS base.
    ../../../modules/shared
    ../../../modules/nixos/common.nix
  ];

  # Networking with VLAN support for GitHub runners.
  networking = {
    hostName = "garfield";
    networkmanager.enable = false;  # Disabled for manual VLAN control
    useNetworkd = true;             # systemd-networkd for VLAN support
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 8123 ];  # SSH, Home Assistant
    };

    # VLAN interfaces on eno0 (adjust if not eno0 - check with `ip link`).
    vlans = {
      "eno0.10" = {
        id = 10;
        interface = "eno0";
      };
      "eno0.20" = {
        id = 20;
        interface = "eno0";
      };
    };

    interfaces = {
      eno0 = {};
      "eno0.10" = {
        ipv4.addresses = [
          { address = "10.0.10.2"; prefixLength = 24; }
        ];
      };
      "eno0.20" = {
        ipv4.addresses = [
          { address = "10.0.20.2"; prefixLength = 24; }
        ];
      };
    };

    # Gateway on VLAN 10
    defaultGateway = {
      address = "10.0.10.1";
      interface = "eno0.10";
    };

    nameservers = [ "10.0.10.1" "1.1.1.1" ];
  };

  time.timeZone = "America/Kentucky/Louisville";

  programs.firefox.enable = true;

  services = {
    # Nvidia graphics.
    xserver.videoDrivers = ["nvidia"];

    # Headless box: log in automatically (gdm itself enabled in common.nix).
    displayManager.autoLogin = {
      enable = true;
      user = "amitsheokand";
    };

    # Ollama: local LLM server (API at http://localhost:11434).
    ollama.enable = true;
  };

  # Host-only packages (core set in common.nix).
  environment.systemPackages = with pkgs; [
    nvidia-container-toolkit  # For containerized GPU workloads
  ];

  # Nvidia/Wayland environment (base Wayland hints in common.nix).
  environment.sessionVariables = {
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  # GPU: Nvidia — base graphics in common.nix; this host adds the driver.
  hardware = {
    nvidia = {
      modesetting.enable = true;

      # Power management (experimental)
      powerManagement.enable = false;
      powerManagement.finegrained = false;

      # Open-source kernel module (for RTX 20 series and newer, driver 515.43.04+)
      open = false;

      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };

    # Intel CPU microcode updates
    cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };

  # Bootloader (loader lives in common.nix); this host pins the kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  system.stateVersion = "25.05";
}
