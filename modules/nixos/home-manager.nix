{ config, pkgs, lib, inputs, ... }:

let
  user = "amitsheokand";
  xdg_configHome  = "/home/${user}/.config";
  shared-programs = import ../shared/home-manager.nix { inherit config pkgs lib; };
  shared-files = import ../shared/files.nix { inherit config pkgs; };
  headroom = import ../shared/headroom.nix { inherit pkgs lib; };
  piModels = pkgs.writeText "pi-qwen38-models.json" (builtins.toJSON {
    providers = {
      "qwen38-local" = {
        baseUrl = "http://127.0.0.1:8080/v1";
        api = "openai-completions";
        apiKey = "local";
        compat = {
          supportsDeveloperRole = false;
          supportsReasoningEffort = false;
        };
        models = [ {
          id = "qwen38";
          name = "Qwen3.8 27B (RX 6700 XT)";
          reasoning = false;
          input = [ "text" ];
          contextWindow = 32768;
          maxTokens = 4096;
          cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
        } ];
      };
    };
  });
in
{
  imports = [ inputs.pi.homeModules.default ];
  home = {
    enableNixpkgsReleaseCheck = false;
    username = "${user}";
    homeDirectory = "/home/${user}";
    sessionVariables = {
      AI_BASE_URL = "http://127.0.0.1:8080/v1";
      AI_MODEL = "qwen38";
      AI_CONTEXT_WINDOW = "32768";
      AI_MAX_TOKENS = "4096";
      GROK_LOCAL_MODEL = "qwen38";
      GROK_LOCAL_BASE_URL = "http://127.0.0.1:8080/v1";
    };
    packages = (pkgs.callPackage ./packages.nix { inherit inputs config; })
      ++ (headroom.home.packages or []);
    file = shared-files
      // import ./files.nix { inherit user pkgs; }
      // (headroom.home.file or {})
      // {
        ".codex/mlx-local.config.toml" = {
          text = ''
            model = "qwen38"
            model_provider = "qwen38-local"
            model_context_window = 32768

            [model_providers.qwen38-local]
            name = "Qwen3.8 27B (RX 6700 XT)"
            base_url = "http://127.0.0.1:8080/v1"
            wire_api = "responses"
            requires_openai_auth = false
          '';
        };
      }
      // import ../shared/ai-tools.nix { inherit pkgs lib user; };
    activation = headroom.home.activation or {};
    stateVersion = "25.11";
  };

  programs = shared-programs // {
    pi.coding-agent = {
      enable = true;
      models = piModels;
      settings.model = "qwen38";
    };
    gpg.enable = true;
  };

  systemd.user.services = headroom.systemd.user.services or {};

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
