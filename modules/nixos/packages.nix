{ pkgs, inputs, config ? null }:
with pkgs;
let
  shared-packages = import ../shared/packages.nix { inherit pkgs; };
in
shared-packages ++ [
  # === Desktop Apps ===
  firefox           # Web browser
  chromium          # Alternative browser
  vlc               # Media player
  gimp              # Image editor

  # === Development Tools (GUI) ===
  ghostty             # GPU-accelerated terminal
  zed-editor          # Modern code editor

  # === Wine for Windows apps ===
  wine              # Windows compatibility layer
  winetricks        # Wine configuration helper

  # === System Tools ===
  bluez             # Bluetooth
  pavucontrol       # Audio controls
  playerctl         # Media player control

  # === CLI Tools ===
  glow              # Terminal markdown viewer
  glances           # System monitoring

  # === GNOME Extensions & Tools ===
  gnome-tweaks      # GNOME customization
  gnomeExtensions.appindicator  # System tray icons
  
  # === Utilities ===
  libnotify         # Desktop notifications
  xclip             # Clipboard from CLI
  wl-clipboard      # Wayland clipboard
  
  # === Graphics ===
  pciutils          # lspci for hardware info
  mesa-demos        # OpenGL utilities
  vulkan-tools      # Vulkan utilities
]
