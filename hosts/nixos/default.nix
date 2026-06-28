{ config, lib, pkgs, modulesPath, user, claude-code-nix, codex-cli-nix, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")

    # Shared cross-platform config (nixpkgs, overlays) + shared NixOS base.
    ../../modules/shared
    ../../modules/nixos/common.nix

    # Systemd services and timers
    ../../modules/nixos/systemd.nix
    # RustDesk self-hosted server (ID + relay for local network)
    ../../modules/nixos/rustdesk-server.nix
    # Sunshine game-stream host (stream this desktop to Moonlight clients)
    ../../modules/nixos/sunshine.nix
  ];

  # Boot configuration (systemd-boot loader lives in common.nix).
  boot = {
    # Zen kernel: gaming/Wine/DXVK tuned, includes futex_waitv + ntsync,
    # in nixpkgs binary cache so no local kernel build required.
    kernelPackages = pkgs.linuxPackages_zen;

    # Headless dGPU (RX 6700 XT, Navi 22): pin at D0, BACO runtime-PM
    # wedges the chip and takes the display path down with it.
    kernelParams = [ "amdgpu.runpm=0" ];

    initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usb_storage" "usbhid" "sd_mod" ];
    initrd.kernelModules        = [];
    kernelModules               = [ "kvm-amd" ];

    # Realtek RTL8852BE (rtw89) Wi-Fi stability: PCIe ASPM lets the card sleep
    # deep enough that firmware misses periodic scans, stalling the link and
    # tearing down Sunshine streams. Disable ASPM + radio low-power mode.
    extraModprobeConfig = ''
      options rtw89_pci disable_aspm_l1=y disable_aspm_l1ss=y
      options rtw89_core disable_ps_mode=y
    '';

    # Increase inotify watch limit to prevent warnings.
    kernel.sysctl = {
      "fs.inotify.max_user_watches" = 1048576;
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

  # GPU: AMD RX 6700 XT — base graphics enabled in common.nix; add ROCm OpenCL.
  hardware.graphics.extraPackages = with pkgs; [
    rocmPackages.clr.icd  # OpenCL ICD for ROCm
  ];

  # GPU/virtualisation groups (base groups in common.nix).
  users.users.${user}.extraGroups = [ "video" "render" "uinput" "libvirtd" "kvm" ];
  users.groups.render = {};
  users.groups.video = {};

  # Windows VM (GNOME Boxes / libvirt) - TPM for Win11, USB redirection.
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
    # Disable Wi-Fi power saving: the rtw89 adapter stalls the link during
    # power-save/scan cycles, which tears down Sunshine streams.
    networkmanager.wifi.powersave = false;
    firewall.enable       = false;
  };

  time.timeZone = "Asia/Kolkata";

  # Desktop GPU uses amdgpu; GNOME fractional-scaling overrides.
  # https://discourse.nixos.org/t/how-to-set-fractional-scaling-via-nix-configuration-for-gnome-wayland/56774
  services.xserver.videoDrivers = ["amdgpu"];
  services.desktopManager.gnome = {
    extraGSettingsOverridePackages = [ pkgs.mutter ];
    extraGSettingsOverrides = ''
      [org.gnome.mutter]
      experimental-features=['scale-monitor-framebuffer', 'xwayland-native-scaling']
    '';
  };

  # Ollama: local LLM server (API at http://localhost:11434).
  services.ollama.enable = true;

  # Host-only packages (core set in common.nix).
  environment.systemPackages = with pkgs; [
    swtpm            # TPM emulator for libvirt (Windows 11 VMs)
  ];

  # Extra binary cache: chaotic-nyx (prebuilt CachyOS kernel & friends).
  nix.settings.substituters = [ "https://chaotic-nyx.cachix.org" ];
  nix.settings.trusted-public-keys = [
    "chaotic-nyx.cachix.org-1:HfnXSw4pj95iI/n17rIDy40agHj12WfF+Gqk6SonIT8="
  ];

  # This value determines the NixOS release from which default settings for
  # stateful data were taken. Leave it at your first install's release.
  system.stateVersion = "25.11";
}
