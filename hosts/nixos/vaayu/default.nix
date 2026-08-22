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
  # 499 MiB ESP: keep 2 kernels (same as odie).
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.systemd-boot.configurationLimit = lib.mkForce 2;

  # Tight root + tiny ESP: GC sooner than the shared 3 gens / 7d.
  programs.nh.clean.extraArgs = lib.mkForce "--keep-since 3d --keep 2";
  nix.settings.min-free = lib.mkForce (4 * 1024 * 1024 * 1024);
  nix.settings.max-free = lib.mkForce (8 * 1024 * 1024 * 1024);

  # No 32-bit userspace on aarch64 Asahi.
  hardware.graphics.enable32Bit = lib.mkForce false;
  services.pipewire.alsa.support32Bit = lib.mkForce false;

  # US Mac keyboard: unswap ` / ~
  boot.extraModprobeConfig = ''
    options hid_apple iso_layout=0
    # NT-personality sync engine: the aikya sync consumer needs /dev/ntsync
    modprobe ntsync
  '';

  networking = {
    hostName = "vaayu";
    networkmanager.enable = true;
    networkmanager.wifi.backend = "iwd";
    firewall.enable = true;
  };

  # iwd + Avahi on lo+wlan0 self-conflicts and republishes as vaayu-2.local,
  # so `ssh vaayu` from the Mac fails DNS. Publish only on Wi-Fi, after the
  # link is up.
  services.avahi = {
    hostName = "vaayu";
    allowInterfaces = [ "wlan0" ];
  };
  systemd.services.avahi-daemon = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
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

  # LAN send + firewall for LocalSend discovery/transfer.
  programs.localsend.enable = true;

  # Minimal extras (core + pi/opencode from llm-agents in common.nix; Cursor from flake).
  environment.systemPackages = with pkgs; [
    firefox
    curl
    wget
    htop
    zed-editor
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
