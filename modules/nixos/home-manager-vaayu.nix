# Slim Home Manager for Asahi MacBook Air (vaayu).
# Shell/git/tmux + Headroom + Pi. GPU inference is on the desktop catalog
# at http://nixos.local:8080/v1 (forge/anvil/feather). OpenRouter stays as
# a Pi extension. No ROCm / ai-tools.
{ config, pkgs, lib, inputs, ... }:

let
  user = "amitsheokand";
  shared-programs = import ../shared/home-manager.nix { inherit config pkgs lib; };
  shared-files = import ../shared/files.nix { inherit config pkgs; };
  headroom = import ../shared/headroom.nix { inherit pkgs lib; };
  commandCode = import ../shared/command-code.nix { inherit pkgs lib; };
  zvecGrep = import ../shared/zvec-grep.nix { inherit pkgs lib; };
  museSpark = import ../shared/muse-spark.nix { inherit pkgs lib; };
  hipfireLan = import ../shared/pi-hipfire-catalog.nix {
    inherit lib;
    baseUrl = "http://nixos.local:8080/v1";
  };
  piAgent = import ../shared/pi-agent.nix {
    inherit pkgs lib;
    pi = inputs.llm-agents-nix.packages.${pkgs.stdenv.hostPlatform.system}.pi;
    # OpenRouter ox-alpha stays via extension. `/model forge` hits desktop LAN.
    localSettings = hipfireLan.piLocalSettings;
    localModels = hipfireLan.piLocalModels;
  };
in
{
  home = {
    enableNixpkgsReleaseCheck = false;
    username = "${user}";
    homeDirectory = "/home/${user}";
    sessionVariables = hipfireLan.sessionVariables
      // (piAgent.sessionVariables or {});
    packages = (headroom.home.packages or [])
      ++ (commandCode.home.packages or [])
      ++ (zvecGrep.home.packages or [])
      ++ (museSpark.home.packages or [])
      ++ (piAgent.home.packages or []);
    file = shared-files
      // import ./files.nix { inherit user pkgs; }
      // (headroom.home.file or {});
    activation = (headroom.home.activation or {})
      // (commandCode.home.activation or {})
      // (zvecGrep.home.activation or {})
      // (museSpark.home.activation or {})
      // piAgent.activation;
    sessionPath = (commandCode.home.sessionPath or [])
      ++ (zvecGrep.home.sessionPath or [])
      ++ (headroom.home.sessionPath or []);
    stateVersion = "25.11";
  };

  programs = shared-programs // { gpg.enable = true; };

  systemd.user.services = (headroom.systemd.user.services or {})
    // (museSpark.systemdUserServices or {})
    // (zvecGrep.systemdUserServices or {});

  xdg.configFile = {
    "systemd/user/muse-spark-proxy.service".force = true;
    "systemd/user/zvec-grep.service".force = true;
  };

  services.gpg-agent = {
    enable = true;
    enableSshSupport = false;
    pinentry.package = pkgs.pinentry-gnome3;
  };

  dconf.settings = {
    "org/gnome/mutter" = {
      experimental-features = [ "scale-monitor-framebuffer" "xwayland-native-scaling" ];
    };
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita";
      icon-theme = "Adwaita";
      # M1 Air Retina — start at 200% integer; adjust in Displays if needed.
      scaling-factor = 2;
    };
    "org/gnome/GPaste" = {
      primary-to-history = false;
      synchronize-clipboards = false;
    };
    "org/gnome/desktop/input-sources" = {
      xkb-options = [ "ctrl:nocaps" "terminate:ctrl_alt_bksp" ];
    };
    "org/gnome/desktop/wm/preferences" = {
      focus-mode = "click";
      button-layout = "appmenu:minimize,maximize,close";
    };
    "org/gnome/shell" = {
      favorite-apps = [
        "firefox.desktop"
        "org.gnome.Nautilus.desktop"
        "org.gnome.Console.desktop"
        "cursor.desktop"
      ];
      enabled-extensions = [
        "appindicatorsupport@rgcjonas.gmail.com"
      ];
    };
  };
}
