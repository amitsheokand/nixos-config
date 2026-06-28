# Shared NixOS base imported by every Linux host (nixos, garfield, odie).
# Host files keep only what's genuinely host-specific: hostname/networking,
# GPU drivers + kernel, hardware-configuration.nix, timezone, stateVersion,
# and host-only packages/services. Everything identical across hosts lives here.
{ config, lib, pkgs, user, claude-code-nix, codex-cli-nix, ... }:

{
  # Hardware platform default (hosts may override).
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Locale (identical on every host).
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS        = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT    = "en_US.UTF-8";
    LC_MONETARY       = "en_US.UTF-8";
    LC_NAME           = "en_US.UTF-8";
    LC_NUMERIC        = "en_US.UTF-8";
    LC_PAPER          = "en_US.UTF-8";
    LC_TELEPHONE      = "en_US.UTF-8";
    LC_TIME           = "en_US.UTF-8";
  };

  programs.zsh.enable = true;

  # Clipboard history manager (GNOME-native: daemon + Shell extension + CLI).
  # Recall past copies via the panel icon or Ctrl+Alt+H. Works on Wayland.
  # NOTE: tracks the CLIPBOARD (Ctrl+C / Ctrl+V), NOT the PRIMARY / middle-click
  # buffer — paste in terminals with Ctrl+Shift+V to read what you copied.
  programs.gpaste.enable = true;

  # Virtual-terminal keymap follows the X keyboard config below.
  console.useXkbConfig = true;

  services = {
    # Keyboard layout shared by all hosts; each host sets its own videoDrivers.
    xserver = {
      enable = true;
      xkb = {
        layout = "us";
        options = "ctrl:nocaps";
      };
    };

    # GNOME on GDM everywhere.
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;

    # Advertise <host>.local over mDNS for SSH / RustDesk by name.
    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };

    printing.enable = true;

    # Audio via PipeWire (PulseAudio off).
    pulseaudio.enable = false;
    pipewire = {
      enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
    };

    openssh.enable = true;
    blueman.enable = true;
  };

  # Bluetooth + base graphics (hosts add GPU-specific extraPackages).
  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
    graphics = {
      enable = true;
      enable32Bit = true;  # 32-bit graphics for Wine/DXVK
    };
  };

  # systemd-boot on EFI (hosts pick kernelPackages / kernelParams).
  boot.loader = {
    systemd-boot = {
      enable             = true;
      configurationLimit = 5;
    };
    efi.canTouchEfiVariables = true;
  };

  # Primary user (hosts append extra groups, e.g. video/render/libvirtd).
  users.users.${user} = {
    isNormalUser = true;
    description  = "Amit Sheokand";
    extraGroups  = [ "networkmanager" "wheel" ];
    shell = pkgs.zsh;
  };

  # Passwordless reboot + nixos-rebuild for the wheel group.
  security.sudo = {
    enable     = true;
    extraRules = [
      {
        commands = [
          {
            command = "${pkgs.systemd}/bin/reboot";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/nixos-rebuild";
            options = [ "NOPASSWD" ];
          }
        ];
        groups = [ "wheel" ];
      }
    ];
  };

  # Electron / Wayland hints (GNOME Wayland on every host).
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "wayland";
  };

  # Core packages present on every host (hosts add their own extras).
  environment.systemPackages = with pkgs; [
    vim
    git
    claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
    codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
    wl-clipboard     # Wayland clipboard utilities
    wayland-utils    # Wayland utilities
    lm_sensors       # Hardware monitoring sensors
  ];

  fonts.packages = import ../shared/fonts.nix { inherit pkgs; };

  # Nix daemon settings (hosts may append extra substituters / keys).
  nix = {
    nixPath = [
      "nixos-config=/home/${user}/.local/share/src/nixos-config:/etc/nixos"
    ];
    settings = {
      allowed-users       = [ "${user}" ];
      trusted-users       = [ "@admin" "${user}" "root" ];
      substituters        = [
        "https://nix-community.cachix.org"
        "https://cache.nixos.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
      experimental-features = [ "nix-command" "flakes" ];
    };
    package      = pkgs.nix;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';

    gc = {
      automatic = true;
      dates     = "weekly";
      options   = "--delete-older-than 7d";
    };
    optimise.automatic = true;
  };
}
