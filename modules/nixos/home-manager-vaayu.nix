# Slim Home Manager for Asahi MacBook Air (vaayu).
# Shell/git/tmux + Headroom + Pi (OpenRouter). No local qwen38 / ROCm / ai-tools.
{ config, pkgs, lib, inputs, ... }:

let
  user = "amitsheokand";
  shared-programs = import ../shared/home-manager.nix { inherit config pkgs lib; };
  shared-files = import ../shared/files.nix { inherit config pkgs; };
  headroom = import ../shared/headroom.nix { inherit pkgs lib; };
  piAgent = import ../shared/pi-agent.nix {
    inherit pkgs lib;
    pi = inputs.llm-agents-nix.packages.${pkgs.stdenv.hostPlatform.system}.pi;
    # Prefer OpenRouter ox-alpha via extension; no local llama defaults.
    localSettings = { };
    localModels = null;
  };
in
{
  home = {
    enableNixpkgsReleaseCheck = false;
    username = "${user}";
    homeDirectory = "/home/${user}";
    packages = (headroom.home.packages or [])
      ++ (piAgent.home.packages or []);
    file = shared-files
      // import ./files.nix { inherit user pkgs; }
      // (headroom.home.file or {});
    activation = (headroom.home.activation or {}) // piAgent.activation;
    stateVersion = "25.11";
  };

  programs = shared-programs // { gpg.enable = true; };

  systemd.user.services = headroom.systemd.user.services or {};

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
