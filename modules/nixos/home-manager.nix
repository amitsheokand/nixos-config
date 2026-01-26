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
    stateVersion = "25.05";
  };

  programs = shared-programs // { 
    gpg.enable = true;
  };

  # GNOME-specific settings via dconf
  dconf.settings = {
    # Dark theme
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita-dark";
    };
    
    # Keyboard settings
    "org/gnome/desktop/input-sources" = {
      xkb-options = ["ctrl:nocaps"];
    };
    
    # Window management
    "org/gnome/desktop/wm/preferences" = {
      focus-mode = "click";
    };
    
    # Terminal keybinding
    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
      ];
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      binding = "<Super>Return";
      command = "alacritty";
      name = "Terminal";
    };
  };
}
