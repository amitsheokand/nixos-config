{ config, pkgs, lib, inputs, osConfig ? {}, ... }:

let
  user = "amitsheokand";
  xdg_configHome  = "/home/${user}/.config";
  shared-programs = import ../shared/home-manager.nix { inherit config pkgs lib; };
  shared-files = import ../shared/files.nix { inherit config pkgs; };
  headroom = import ../shared/headroom.nix { inherit pkgs lib; };
  commandCode = import ../shared/command-code.nix { inherit pkgs lib; };
  zvecGrep = import ../shared/zvec-grep.nix { inherit pkgs lib; };
  museSpark = import ../shared/muse-spark.nix { inherit pkgs lib; };
  hipfireEnabled = (osConfig.networking.hostName or "") == "nixos";
  hipfireLocal = if hipfireEnabled
    then import ../shared/hipfire-local.nix { inherit pkgs lib user; }
    else null;
  hipfireLan = import ../shared/pi-hipfire-catalog.nix {
    inherit lib;
    baseUrl = "http://nixos.local:8080/v1";
  };
  piAgent = import ../shared/pi-agent.nix {
    inherit pkgs lib;
    pi = inputs.llm-agents-nix.packages.${pkgs.stdenv.hostPlatform.system}.pi;
    localSettings = if hipfireLocal != null
      then hipfireLocal.piLocalSettings
      else hipfireLan.piLocalSettings;
    localModels = if hipfireLocal != null
      then hipfireLocal.piLocalModels
      else hipfireLan.piLocalModels;
  };
in
{
  home = {
    enableNixpkgsReleaseCheck = false;
    username = "${user}";
    homeDirectory = "/home/${user}";
    sessionVariables = (if hipfireLocal == null
      then hipfireLan.sessionVariables
      else hipfireLocal.sessionVariables)
      // (piAgent.sessionVariables or {});
    packages = (pkgs.callPackage ./packages.nix { inherit inputs config; })
      ++ (headroom.home.packages or [])
      ++ (commandCode.home.packages or [])
      ++ (zvecGrep.home.packages or [])
      ++ (museSpark.home.packages or [])
      ++ (piAgent.home.packages or [])
      ++ (if hipfireLocal == null then [] else hipfireLocal.packages);
    file = shared-files
      // import ./files.nix { inherit user pkgs; }
      // (headroom.home.file or {})
      // (zvecGrep.home.file or {})
      // import ../shared/ai-tools.nix { inherit pkgs lib user; };
    activation = (headroom.home.activation or {})
      // (commandCode.home.activation or {})
      // (zvecGrep.home.activation or {})
      // (museSpark.home.activation or {})
      // piAgent.activation
      // (if hipfireLocal == null then {} else {
        mergeHipfireCatalogClients = lib.hm.dag.entryAfter [ "writeBoundary" ] hipfireLocal.catalogMergeScript;
      });
    sessionPath = (commandCode.home.sessionPath or [])
      ++ (zvecGrep.home.sessionPath or [])
      ++ (headroom.home.sessionPath or []);
    stateVersion = "25.11";
  };

  programs = shared-programs // { gpg.enable = true; };

  systemd.user.services = (headroom.systemd.user.services or {})
    // (museSpark.systemdUserServices or {})
    // (zvecGrep.systemdUserServices or {})
    // (if hipfireLocal == null then {} else hipfireLocal.systemdUserServices);

  # `systemctl --user mask` leaves ~/.config/systemd/user/*.service -> /dev/null.
  # HM then refuses to clobber those links and activation fails. Force overwrite
  # so a leftover mask cannot block nixos-rebuild.
  xdg.configFile = lib.mkMerge [
    {
      "systemd/user/muse-spark-proxy.service".force = true;
      "systemd/user/zvec-grep.service".force = true;
    }
    (lib.mkIf hipfireEnabled {
      "systemd/user/hipfire-serve.service".force = true;
      "systemd/user/hipfire-daemon-watch.service".force = true;
      "systemd/user/pi-compact-router.service".force = true;
      "systemd/user/pi-compact-tiny.service".force = true;
      # Live `systemctl --user enable` left these wants links; HM must overwrite them.
      "systemd/user/default.target.wants/pi-compact-router.service".force = true;
      "systemd/user/default.target.wants/pi-compact-tiny.service".force = true;
    })
  ];

  # GPG agent with pinentry for passphrase prompts
  services.gpg-agent = {
    enable = true;
    enableSshSupport = false;
    pinentry.package = pkgs.pinentry-gnome3;
  };

  # GNOME-specific settings via dconf
  dconf.settings = {
    # Enable fractional scaling (125%, 150%, 175% in Displays)
    "org/gnome/mutter" = {
      experimental-features = [ "scale-monitor-framebuffer" "xwayland-native-scaling" ];
    };
    # Dark theme + 150% fractional scaling (Wayland)
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita";
      icon-theme = "Adwaita";
      scaling-factor = 1.5;  # 150%
    };

    # Keep Ctrl+C/Ctrl+V independent from PRIMARY selection. If GPaste syncs
    # PRIMARY into CLIPBOARD, selecting text in another app can overwrite the
    # content you just copied before you paste it.
    "org/gnome/GPaste" = {
      primary-to-history = false;
      synchronize-clipboards = false;
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
