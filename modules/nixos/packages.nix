{ pkgs, inputs, config ? null }:
with pkgs;
let
  shared-packages = import ../shared/packages.nix { inherit pkgs; };
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
  code-cursor

  # === Development Tools (GUI) ===
  ghostty             # GPU-accelerated terminal
  zed-editor          # Modern code editor
  jetbrains.rust-rover # Rust IDE

  # === System Tools ===
  bluez             # Bluetooth
  pavucontrol       # Audio controls
  playerctl         # Media player control
  rustdesk          # Remote desktop (client; server runs via rustdesk-server module)

  # === Windows VM (GNOME Boxes / libvirt) ===
  gnome-boxes        # VM management (libvirt wrapper)
  dnsmasq            # VM networking
  phodav             # Share files with guest VMs

  # === CLI Tools ===
  glow              # Terminal markdown viewer
  glances           # System monitoring

  # === GNOME Extensions & Tools ===
  gnome-tweaks      # GNOME customization
  gnomeExtensions.appindicator      # System tray icons
  gnomeExtensions.dash-to-dock      # Dock customization
  gnomeExtensions.dash-to-panel     # Panel mode for dock
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
  
  # === ROCm for AMD GPU compute (RX 6700 XT / gfx1031) ===
  rocmPackages.rocm-smi       # GPU monitoring
  rocmPackages.rocminfo       # ROCm device info
  rocmPackages.clr            # ROCm runtime (includes HIP)
]
