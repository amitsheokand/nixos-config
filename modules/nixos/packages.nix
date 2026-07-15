{ pkgs, inputs, config ? null }:
with pkgs;
let
  shared-packages = import ../shared/packages.nix { inherit pkgs; };
  zed-xwayland = symlinkJoin {
    name = "zed-editor-xwayland";
    paths = [ zed-editor ];
    buildInputs = [ makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/zeditor --set WAYLAND_DISPLAY ""
    '';
  };
  rustdesk-hwcodec = import ./rustdesk-package.nix { inherit pkgs; };
  bonsai-llama-vulkan = import ./bonsai-package.nix { inherit pkgs; };
  bonsai-tools = import ./bonsai-tools.nix { inherit pkgs bonsai-llama-vulkan; };
in
shared-packages ++ [
  # === Desktop Apps ===
  firefox           # Web browser
  brave             # Privacy-focused browser
  chromium          # Alternative browser
  spotify           # Music streaming
  vlc               # Media player
  gimp              # Image editor
  localsend         # File transfer

  # === Development Tools (GUI) ===
  ghostty             # GPU-accelerated terminal
  zed-xwayland        # Modern code editor; XWayland avoids Zed Wayland clipboard bugs
  vscodium            # VS Code without telemetry

  # === System Tools ===
  bluez             # Bluetooth
  pavucontrol       # Audio controls
  playerctl         # Media player control
  rustdesk-hwcodec  # Official AppImage with VA-API hardware codecs

  # === Windows VM (GNOME Boxes / libvirt) ===
  gnome-boxes        # VM management (libvirt wrapper)
  dnsmasq            # VM networking
  phodav             # Share files with guest VMs

  # === CLI Tools ===
  glow              # Terminal markdown viewer
  glances           # System monitoring
  bubblewrap        # Sandboxing (required by Codex CLI)
  bonsai-llama-vulkan # PrismML llama.cpp fork for Bonsai Q1_0/Q2_0 on AMD Vulkan
  bonsai-tools.download # Resumable Ternary-Bonsai 27B model download
  bonsai-tools.server   # Local OpenAI-compatible server and web UI
  bonsai-tools.bench    # RX 6700 XT prompt/decode benchmark

  # === GNOME Extensions & Tools ===
  gnome-tweaks      # GNOME customization
  gnomeExtensions.appindicator      # System tray icons
  gnomeExtensions.dash-to-dock      # Dock customization
  gnomeExtensions.arcmenu           # Application menu
  gnomeExtensions.blur-my-shell     # Blur effects
  gnomeExtensions.just-perfection   # GNOME UI tweaks
  
  # === Utilities ===
  libnotify         # Desktop notifications
  xclip             # Clipboard from CLI
  wl-clipboard      # Wayland clipboard
  
  # === Graphics ===
  pciutils          # lspci for hardware info
  mesa-demos        # OpenGL utilities
  vulkan-tools      # Vulkan utilities
  amdgpu_top        # Per-process VRAM/GTT usage for AMD GPUs
  
  # === ROCm for AMD GPU compute (RX 6700 XT / gfx1031) ===
  rocmPackages.rocm-smi       # GPU monitoring
  rocmPackages.rocminfo       # ROCm device info
  rocmPackages.clr            # ROCm runtime (includes HIP)
]
