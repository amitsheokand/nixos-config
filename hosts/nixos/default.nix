{ config, lib, pkgs, modulesPath, user, claude-code-nix, codex-cli-nix, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")

    # Import shared configuration (tmux, zsh, packages, etc.)
    # Comment these out initially if you want to start completely minimal
    ../../modules/shared
    
    # Systemd services and timers
    ../../modules/nixos/systemd.nix
    # RustDesk self-hosted server (ID + relay for local network)
    ../../modules/nixos/rustdesk-server.nix

  ];

  # Boot configuration
  boot = {
    loader.systemd-boot = {
      enable             = true;
      configurationLimit = 5;
    };
    loader.efi.canTouchEfiVariables = true;

    # Zen kernel: gaming/Wine/DXVK tuned, includes futex_waitv + ntsync,
    # in nixpkgs binary cache so no local kernel build required.
    # (CachyOS via chaotic-nyx was tried but its overlay's replaceStdenv
    # doesn't compose with nixpkgs-unstable when nixpkgs.follows is set,
    # and removing follows breaks the overlay interface entirely.)
    kernelPackages = pkgs.linuxPackages_zen;

    # Headless dGPU (RX 6700 XT, Navi 22): pin at D0, BACO runtime-PM
    # wedges the chip and takes the display path down with it.
    kernelParams = [ "amdgpu.runpm=0" ];

    initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usb_storage" "usbhid" "sd_mod" ];
    initrd.kernelModules        = [];
    kernelModules               = [ "kvm-amd" ];

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
      enable32Bit = true;  # 32-bit support for Steam
      # ROCm OpenCL support for RX 6700 XT
      extraPackages = with pkgs; [
        rocmPackages.clr.icd  # OpenCL ICD for ROCm
      ];
    };
  };

  # Add user to video/render groups for GPU access
  users.groups.render = {};
  users.groups.video = {};

  # Windows VM (GNOME Boxes / libvirt) - TPM for Win11, USB redirection
  # See: https://crescentro.se/posts/windows-vm-nixos/
  # OVMF is included with QEMU by default (ovmf submodule was removed in nixpkgs)
  virtualisation.libvirtd = {
    enable = true;
    qemu.swtpm.enable = true;
  };
  virtualisation.spiceUSBRedirection.enable = true;

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
    

    # GNOME Desktop Environment (fractional scaling: https://discourse.nixos.org/t/how-to-set-fractional-scaling-via-nix-configuration-for-gnome-wayland/56774)
    displayManager.gdm.enable = true;
    desktopManager.gnome = {
      enable = true;
      extraGSettingsOverridePackages = [ pkgs.mutter ];
      extraGSettingsOverrides = ''
        [org.gnome.mutter]
        experimental-features=['scale-monitor-framebuffer', 'xwayland-native-scaling']
      '';
    };

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

    # Ollama: local LLM server (API at http://localhost:11434)
    # Ref: https://wiki.nixos.org/wiki/Ollama
    ollama.enable = true;
  };

  # Define a user account
  users.users.${user} = {
    isNormalUser = true;
    description  = "Amit Sheokand";
    extraGroups  = [ "networkmanager" "wheel" "video" "render" "libvirtd" "kvm" ];
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
    claude-code-nix.packages.${pkgs.system}.default
    codex-cli-nix.packages.${pkgs.system}.default
    wl-clipboard     # Wayland clipboard utilities (replaces xclip)
    wayland-utils    # Wayland utilities
    lm_sensors       # Hardware monitoring sensors
    btop             # Modern resource monitor with temp display
    swtpm            # TPM emulator for libvirt (Windows 11 VMs)
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
        # Chaotic-nyx cache: prebuilt CachyOS kernel & friends
        "https://chaotic-nyx.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "chaotic-nyx.cachix.org-1:HfnXSw4pj95iI/n17rIDy40agHj12WfF+Gqk6SonIT8="
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
