{ config, pkgs, lib, home-manager, pi, ... }:

let
  user           = "amitsheokand";
  sharedFiles     = import ../shared/files.nix { inherit config pkgs; };
  additionalFiles = import ./files.nix { inherit user config pkgs; };
  piModels = pkgs.writeText "pi-mlx-models.json" (builtins.toJSON {
    providers = {
      "mlx-local" = {
        baseUrl = "http://127.0.0.1:8080/v1";
        api = "openai-completions";
        apiKey = "local";
        compat = {
          supportsDeveloperRole = false;
          supportsReasoningEffort = false;
        };
        models = [ {
          id = "/Users/amitsheokand/models/DeepSeek-V4-Pro-Qwen3.5-9B-4bit";
          name = "DeepSeek V4 Pro Qwen3.5 9B (MLX)";
          reasoning = false;
          input = [ "text" ];
          contextWindow = 65536;
          maxTokens = 4096;
          cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
        } ];
      };
    };
  });
in
{
  users.users.${user} = {
    name     = "${user}";
    home     = "/Users/${user}";
    isHidden = false;
    shell    = pkgs.zsh;
  };

  homebrew = {
    # This is a module from nix-darwin
    # Homebrew is *installed* via the flake input nix-homebrew
    # Docs: https://github.com/zhaofengli/nix-homebrew
    enable = true;

    # Homebrew casks (GUI apps)
    casks = pkgs.callPackage ./casks.nix {};
    
    # Homebrew formulae (CLI tools)
    # brews = [];
    
    # Mac App Store apps (requires mas CLI)
    # $ nix shell nixpkgs#mas
    # $ mas search <app name>
    # masApps = {
    #   "hidden-bar" = 1452453066;
    # };
  };

  home-manager = {
    useGlobalPkgs = true;
    users.${user} = { pkgs, config, lib, ... }:
      let
        headroom = import ../shared/headroom.nix { inherit pkgs lib; };
      in
      {
        imports = [ pi.homeModules.default ];
        home = {
          enableNixpkgsReleaseCheck = false;
          sessionVariables = {
            AI_BASE_URL = "http://127.0.0.1:8080/v1";
            AI_MODEL = "/Users/amitsheokand/models/DeepSeek-V4-Pro-Qwen3.5-9B-4bit";
            AI_CONTEXT_WINDOW = "65536";
            AI_MAX_TOKENS = "4096";
            GROK_LOCAL_MODEL = "/Users/amitsheokand/models/DeepSeek-V4-Pro-Qwen3.5-9B-4bit";
            GROK_LOCAL_BASE_URL = "http://127.0.0.1:8080/v1";
          };
          packages = (pkgs.callPackage ./packages.nix {})
            ++ (headroom.home.packages or []);
          file = lib.mkMerge [
            sharedFiles
            additionalFiles
            (headroom.home.file or {})
            {
              ".codex/mlx-local.config.toml" = {
                text = ''
                  model = "/Users/amitsheokand/models/DeepSeek-V4-Pro-Qwen3.5-9B-4bit"
                  model_provider = "mlx-local"
                  model_context_window = 65536

                  [model_providers.mlx-local]
                  name = "DeepSeek V4 Pro Qwen3.5 9B (MLX)"
                  base_url = "http://127.0.0.1:8080/v1"
                  wire_api = "responses"
                  requires_openai_auth = false
                '';
              };
            }
            (import ../shared/ai-tools.nix { inherit pkgs lib user; })
          ];
          activation = headroom.home.activation or {};
          stateVersion = "23.11";
        };
        programs = {
          pi.coding-agent = {
            enable = true;
            models = piModels;
            settings.model = "/Users/amitsheokand/models/DeepSeek-V4-Pro-Qwen3.5-9B-4bit";
          };
        } // import ../shared/home-manager.nix { inherit config pkgs lib; };
        manual.manpages.enable = false;
      };
  };
}
