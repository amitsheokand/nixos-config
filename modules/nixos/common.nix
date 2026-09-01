# Shared NixOS base imported by every Linux host (nixos, garfield, odie).
# Host files keep only what's genuinely host-specific: hostname/networking,
# GPU drivers + kernel, hardware-configuration.nix, timezone, stateVersion,
# and host-only packages/services. Everything identical across hosts lives here.
{ config, lib, pkgs, user, llm-agents-nix, ... }:

let
  agents = llm-agents-nix.packages.${pkgs.stdenv.hostPlatform.system};
in
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

  # nix-community nh: nicer switch + generation cleanup (also covers HM profiles).
  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      extraArgs = "--keep-since 7d --keep 3";
    };
  };

  # Allow uv/pipx-installed native wheels (onnxruntime, etc.) to find
  # libstdc++ and friends — required for Headroom proxy on NixOS.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc
      zlib
      openssl
      curl
      icu
      libxml2
    ];
  };

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
        support32Bit = lib.mkDefault pkgs.stdenv.hostPlatform.isx86_64;
      };
      pulse.enable = true;
    };

    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        # Password stays on until vaayu pubkey is in ssh-keys.nix; then set false.
        PasswordAuthentication = true;
      };
    };
    blueman.enable = true;
  };

  # LAN SSH server host keys (TOFU-free). User keys stay in ssh-keys.nix.
  programs.ssh.knownHosts = (import ../shared/ssh-host-keys.nix).knownHosts;

  # Bluetooth + base graphics (hosts add GPU-specific extraPackages).
  # enable32Bit is x86_64-only (Wine/DXVK); Asahi aarch64 hosts mkForce false.
  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
    graphics = {
      enable = true;
      enable32Bit = lib.mkDefault pkgs.stdenv.hostPlatform.isx86_64;
    };
  };

  # systemd-boot on EFI (hosts pick kernelPackages / kernelParams).
  # Keep few ESP copies so small Asahi/Windows ESPs cannot fill (odie forces 2).
  boot.loader = {
    systemd-boot = {
      enable             = true;
      configurationLimit = 3;
      editor             = false;
    };
    efi.canTouchEfiVariables = true;
  };
  boot.tmp.cleanOnBoot = true;

  # Primary user (hosts append extra groups, e.g. video/render/libvirtd).
  users.users.${user} = {
    isNormalUser = true;
    description  = "Amit Sheokand";
    extraGroups  = [ "networkmanager" "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = import ../shared/ssh-keys.nix;
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
          {
            command = "${pkgs.nh}/bin/nh";
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
  # Agent CLIs from llm-agents.nix: pi + OpenCode + Hermes.
  # Cursor is pkgs.code-cursor / cask. Claude / Codex / Grok / prime-agent omitted.
  # Command Code (npm `cmd`) via HM modules/shared/command-code.nix.
  # OpenCode GUI: pkgs.opencode-desktop (CLI comes from agents.opencode).
  # Git: gh/glab (nixpkgs); GitButler GUI+CLI from llm-agents.nix (newer than nixpkgs).
  # rgitui: not in nixpkgs/llm-agents — official x86_64 binary (no aarch64-linux release).
  environment.systemPackages = with pkgs; [
    vim
    git
    gh
    glab
    agents.pi
    agents.opencode
    agents.hermes-agent
    agents.hermes-desktop
    agents.gitbutler
    agents.but
    opencode-desktop
    wl-clipboard     # Wayland clipboard utilities
    wayland-utils    # Wayland utilities
    lm_sensors       # Hardware monitoring sensors
  ] ++ lib.optional pkgs.stdenv.hostPlatform.isx86_64 (
    pkgs.callPackage ../shared/rgitui-package.nix { }
  );

  fonts.packages = import ../shared/fonts.nix { inherit pkgs; };

  # Nix daemon settings (hosts may append extra substituters / keys).
  nix = {
    nixPath = [
      "nixos-config=/home/${user}/.local/share/src/nixos-config:/etc/nixos"
    ];
    settings = {
      allowed-users       = [ "${user}" ];
      trusted-users       = [ "@admin" "${user}" "root" ];
      auto-optimise-store = true;
      # Auto-GC when the volume is tight (odies /boot + root have filled before).
      min-free            = 2 * 1024 * 1024 * 1024;
      max-free            = 10 * 1024 * 1024 * 1024;
      substituters        = [
        "https://nix-community.cachix.org"
        "https://cache.nixos.org"
        "https://cache.numtide.com"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      ];
      experimental-features = [ "nix-command" "flakes" ];
    };
    package      = pkgs.nix;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';

    # Generation GC is programs.nh.clean (keeps 3 gens / 7d). Store hardlinks:
    optimise.automatic = true;
  };
}
