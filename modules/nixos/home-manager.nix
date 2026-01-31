{ config, pkgs, lib, inputs, ... }:

let
  user = "amitsheokand";
  xdg_configHome  = "/home/${user}/.config";
  shared-programs = import ../shared/home-manager.nix { inherit config pkgs lib; };
  shared-files = import ../shared/files.nix { inherit config pkgs; };
in
{
  home = {
    enableNixpkgsReleaseCheck = false;
    username = "${user}";
    homeDirectory = "/home/${user}";
    packages = pkgs.callPackage ./packages.nix { inherit inputs config; };
    file = shared-files // import ./files.nix { inherit user pkgs; };
    stateVersion = "25.11";
  };

  programs = shared-programs // { 
    gpg.enable = true;
  };

  # GPG agent with pinentry for passphrase prompts
  services.gpg-agent = {
    enable = true;
    enableSshSupport = false;
    pinentry.package = pkgs.pinentry-gnome3;
  };

  # GNOME-specific settings via dconf
  dconf.settings = {
    # Dark theme
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita";
      icon-theme = "Adwaita";
    };
    
    # Keyboard settings
    "org/gnome/desktop/input-sources" = {
      xkb-options = ["ctrl:nocaps" "terminate:ctrl_alt_bksp"];
    };
    
    # Window management
    "org/gnome/desktop/wm/preferences" = {
      focus-mode = "click";
      button-layout = "appmenu:minimize,maximize,close";
    };
    
    # Favorite apps in dock
    "org/gnome/shell" = {
      favorite-apps = [
        "firefox.desktop"
        "org.gnome.Nautilus.desktop"
        "org.gnome.Calendar.desktop"
        "spotify.desktop"
        "org.gnome.Console.desktop"
      ];
      enabled-extensions = [
        "appindicatorsupport@rgcjonas.gmail.com"
        "dash-to-dock@micxgx.gmail.com"
        "dash-to-panel@jderose9.github.com"
        "arcmenu@arcmenu.com"
        "blur-my-shell@aunetx"
        "just-perfection-desktop@just-perfection"
      ];
    };
    
    # Terminal keybinding
    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
      ];
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      binding = "<Super>Return";
      command = "ghostty";
      name = "Terminal";
    };
  };
}
