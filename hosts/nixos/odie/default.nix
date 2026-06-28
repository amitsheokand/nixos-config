{ config, lib, pkgs, modulesPath, user, inputs, claude-code-nix, codex-cli-nix, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./hardware-configuration.nix

    # Shared cross-platform config (nixpkgs, overlays) + shared NixOS base.
    ../../../modules/shared
    ../../../modules/nixos/common.nix
  ];

  # Networking - roaming laptop, NetworkManager drives Wi-Fi/Ethernet.
  networking = {
    hostName        = "odie";
    networkmanager.enable = true;
    # Portable machine: keep the firewall on (unlike the desktop `nixos` host).
    firewall.enable = true;
  };

  time.timeZone = "Asia/Kolkata";

  # Swap: no free partition (Windows dual-boot fills the NVMe), so use a
  # declarative swapfile on the ext4 root. NixOS creates it, runs mkswap, and
  # swaps it on at boot. 32 GiB (= RAM) gives a large OOM cushion; this size
  # also leaves room to enable hibernate later (needs resumeDevice + offset).
  swapDevices = [
    {
      device = "/var/swapfile";
      size   = 32 * 1024;  # MiB → 32 GiB
    }
  ];

  programs.firefox.enable = true;

  services = {
    # Intel iGPU uses the generic modesetting (KMS) driver.
    xserver.videoDrivers = ["modesetting"];

    # Touchpad / pointer (laptop)
    libinput.enable = true;

    # Laptop power & thermal management.
    # NOTE: TLP and power-profiles-daemon conflict; using TLP, so disable PPD.
    power-profiles-daemon.enable = false;
    tlp.enable = true;
    thermald.enable = true;   # Intel thermal daemon

    # Fingerprint reader (no-op if the laptop has none; safe to leave on).
    fprintd.enable = true;
  };

  # Laptop GPU access (base groups in common.nix).
  users.users.${user}.extraGroups = [ "video" "render" ];

  # Host-only packages (core set in common.nix).
  environment.systemPackages = with pkgs; [
    moonlight-qt     # Sunshine/GameStream client for the main nixos desktop
    powertop         # Power consumption diagnostics (laptop)
  ];

  # GPU: Intel iGPU — base graphics in common.nix; add the Intel media stack.
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver   # iHD VAAPI driver (Broadwell+ / Gen8+)
    vpl-gpu-rt           # oneVPL runtime for QuickSync
  ];
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Bootloader (loader lives in common.nix); this host pins the kernel.
  # Zen kernel: recent, gaming/Wine-tuned, in the binary cache. Works fine on
  # Intel; drop to pkgs.linuxPackages_latest if you hit a hardware quirk.
  boot.kernelPackages = pkgs.linuxPackages_zen;
  boot.kernelModules  = [ "kvm-intel" ];

  system.stateVersion = "25.05";
}
