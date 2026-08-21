{ config, lib, pkgs, modulesPath, user, inputs, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./hardware-configuration.nix

    # Shared cross-platform config (nixpkgs, overlays) + shared NixOS base.
    ../../../modules/shared
    ../../../modules/nixos/common.nix
  ];

  # Apple Silicon / Asahi (kernel + U-Boot from nixos-apple-silicon).
  hardware.asahi.enable = true;
  nixpkgs.hostPlatform = lib.mkForce "aarch64-linux";

  # ESP is managed by Asahi m1n1/U-Boot — never touch EFI variables.
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.systemd-boot.configurationLimit = lib.mkForce 3;

  # No 32-bit userspace on aarch64 Asahi.
  hardware.graphics.enable32Bit = lib.mkForce false;
  services.pipewire.alsa.support32Bit = lib.mkForce false;

  # US Mac keyboard: unswap ` / ~
  boot.extraModprobeConfig = ''
    options hid_apple iso_layout=0
  '';

  networking = {
    hostName = "vaayu";
    networkmanager.enable = true;
    networkmanager.wifi.backend = "iwd";
    firewall.enable = true;
  };

  time.timeZone = "Asia/Kolkata";

  # 16 GiB RAM Air — modest swapfile (no dedicated swap partition).
  swapDevices = [
    {
      device = "/var/swapfile";
      size = 8 * 1024; # MiB → 8 GiB
    }
  ];

  services = {
    libinput.enable = true;
    # Prefer TLP over power-profiles-daemon on this laptop.
    power-profiles-daemon.enable = false;
    tlp.enable = true;
  };

  users.users.${user}.extraGroups = [ "video" "render" ];

  # Minimal extras (core + pi/opencode from llm-agents in common.nix; Cursor from flake).
  environment.systemPackages = with pkgs; [
    firefox
    curl
    wget
    htop
  ];

  # Trim GNOME bloat — keep Files, Settings, Terminal, browser, Cursor.
  environment.gnome.excludePackages = with pkgs; [
    gnome-tour
    gnome-contacts
    gnome-maps
    gnome-music
    gnome-weather
    totem
    cheese
    epiphany
    geary
    simple-scan
    yelp
    tali
    iagno
    hitori
    atomix
  ];

  system.stateVersion = "26.11";
}
