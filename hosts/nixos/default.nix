{ config, lib, pkgs, modulesPath, user, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")

    # Import shared configuration (tmux, zsh, packages, etc.)
    # Comment these out initially if you want to start completely minimal
    ../../modules/shared
    
    # Systemd services and timers
    ../../modules/nixos/systemd.nix

  ];

  # Boot configuration
  boot = {
    loader.systemd-boot = {
      enable             = true;
      configurationLimit = 15;
    };
    loader.efi.canTouchEfiVariables = true;

    initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usb_storage" "usbhid" "sd_mod" ];
    initrd.kernelModules        = [];
    kernelModules               = [ "kvm-amd" ];
    
    # Wine binfmt - run .exe files directly (uses WoW64 for 32/64-bit support)
    binfmt.registrations.wine = {
      recognitionType = "extension";
      magicOrExtension = "exe";
      interpreter = "${pkgs.wineWowPackages.stable}/bin/wine";
    };
  };

  # Filesystems
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/root";
      fsType = "ext4";
    };

    "/boot" = {
      device = "/dev/nvme0n1p1";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };
  };

  swapDevices = [
    { device = "/dev/disk/by-label/swap"; }
  ];

  # Hardware platform
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  
  # Hardware support for gaming
  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    graphics = {
      enable = true;
      enable32Bit = true;  # 32-bit support for Steam/Wine
      # ROCm OpenCL support for RX 6700 XT
      extraPackages = with pkgs; [
        rocmPackages.clr.icd  # OpenCL ICD for ROCm
      ];
    };
  };

  # Add user to video/render groups for GPU access
  users.groups.render = {};
  users.groups.video = {};

  # Networking
  networking = {
    hostName        = "nixos";
    useDHCP         = lib.mkDefault true;
    networkmanager.enable = true;
    firewall.enable       = false;
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
    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
    };
  };

  # Console configuration for virtual terminals
  console.useXkbConfig = true;

  # Services configuration
  services = {
    xserver = {
     enable = true;
     videoDrivers = ["amdgpu"];
     xkb = {
       layout = "us";
       options = "ctrl:nocaps";
     };
    };
    

    # GNOME Desktop Environment
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;

    # Enable CUPS to print documents.
    printing.enable = true;

    # Enable sound with PipeWire (PulseAudio disabled in favor of PipeWire).
    pulseaudio.enable = false;

    pipewire = {
      enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
    };

    # Enable the OpenSSH daemon.
    openssh.enable = true;

    # Bluetooth
    blueman.enable = true;
  };

  # Define a user account
  users.users.${user} = {
    isNormalUser = true;
    description  = "Amit Sheokand";
    extraGroups  = [ "networkmanager" "wheel" "video" "render" ];
    shell = pkgs.zsh;
  };

  services.displayManager.autoLogin.enable = false;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  #   $ nix search <pkg>
  environment.systemPackages = with pkgs; [
    vim
    git
    wl-clipboard     # Wayland clipboard utilities (replaces xclip)
    wayland-utils    # Wayland utilities
    lm_sensors       # Hardware monitoring sensors
    btop             # Modern resource monitor with temp display
  ];

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
  fonts.packages = import ../../modules/shared/fonts.nix { inherit pkgs; };

  # Configure Nix settings for flakes and Cachix
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
  };

  # Increase inotify watch limit to prevent warnings
  boot.kernel.sysctl = {
    "fs.inotify.max_user_watches" = 1048576;
  };

  # This value determines the NixOS release from which default
  # settings for stateful data were taken. Leave it at your first
  # install's release unless you know what you're doing.
  system.stateVersion = "25.11";
}
