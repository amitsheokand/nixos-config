{ config, lib, pkgs, modulesPath, user, inputs, claude-code-nix, codex-cli-nix, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./hardware-configuration.nix

    # Import shared configuration (tmux, zsh, home-manager, etc.)
    ../../../modules/shared
  ];

  # Networking - roaming laptop, NetworkManager drives Wi-Fi/Ethernet
  networking = {
    hostName        = "odie";
    networkmanager.enable = true;
    # Portable machine: keep the firewall on (unlike the desktop `nixos` host).
    firewall.enable = true;

    # Advertise odie.local on whatever LAN it joins (RustDesk / SSH by name).
    # avahi (below) does the publishing; this just keeps name resolution working.
  };

  # Set your time zone.
  time.timeZone = "Asia/Kolkata";

  # Select internationalisation properties.
  i18n.defaultLocale      = "en_US.UTF-8";
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

  # Programs configuration
  programs = {
    zsh.enable = true;
    firefox.enable = true;
  };

  # Console configuration for virtual terminals
  console.useXkbConfig = true;

  # Services configuration
  services = {
    # X11 / display: Intel iGPU uses the generic modesetting (KMS) driver.
    xserver = {
     enable = true;
     videoDrivers = ["modesetting"];
     xkb = {
       layout = "us";
       options = "ctrl:nocaps";
     };
    };

    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;

    # Touchpad / pointer (laptop)
    libinput.enable = true;

    # Laptop power & thermal management.
    # NOTE: TLP and power-profiles-daemon conflict; GNOME ships PPD by default.
    # Using TLP here, so disable PPD. Switch the two booleans to prefer PPD.
    power-profiles-daemon.enable = false;
    tlp.enable = true;
    thermald.enable = true;   # Intel thermal daemon

    # Advertise odie.local over mDNS on the current LAN.
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

    # Enable CUPS to print documents.
    printing.enable = true;

    # Sound via PipeWire
    pulseaudio.enable = false;
    pipewire = {
      enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
    };

    # SSH daemon
    openssh.enable = true;

    # Bluetooth tray
    blueman.enable = true;

    # Fingerprint reader (no-op if the laptop has none; safe to leave on).
    fprintd.enable = true;
  };

  # Define a user account
  users.users.${user} = {
    isNormalUser = true;
    description  = "Amit Sheokand";
    extraGroups  = [ "networkmanager" "wheel" "video" "render" ];
    shell = pkgs.zsh;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Electron/Wayland apps (VS Code, Cursor) hint
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "wayland";
  };

  # List packages installed in system profile
  environment.systemPackages = with pkgs; [
    vim
    git
    claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
    codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
    wl-clipboard     # Wayland clipboard utilities
    wayland-utils    # Wayland utilities
    lm_sensors       # Hardware monitoring sensors
    powertop         # Power consumption diagnostics (laptop)
  ];

  # Hardware platform
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Hardware support
  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    graphics = {
      enable = true;
      enable32Bit = true;  # 32-bit graphics for Wine/DXVK
      # Intel media stack: VAAPI + QuickSync (video decode/encode).
      extraPackages = with pkgs; [
        intel-media-driver   # iHD VAAPI driver (Broadwell+ / Gen8+)
        vpl-gpu-rt           # oneVPL runtime for QuickSync
      ];
    };

    # Intel CPU microcode updates
    cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };

  # Bootloader
  boot = {
    loader.systemd-boot = {
      enable             = true;
      configurationLimit = 5;
    };
    loader.efi.canTouchEfiVariables = true;
    # Zen kernel: recent, gaming/Wine-tuned, in the binary cache. Works fine on
    # Intel; drop to pkgs.linuxPackages_latest if you hit a hardware quirk.
    kernelPackages = pkgs.linuxPackages_zen;
    kernelModules  = [ "kvm-intel" ];
  };

  # Don't require password for users in `wheel` group for these commands
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

  # Fonts
  fonts.packages = import ../../../modules/shared/fonts.nix { inherit pkgs; };

  # Configure Nix settings for flakes
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

  system.stateVersion = "25.05";
}
