{ config, pkgs, lib, home-manager, llm-agents-nix, ... }:

let
  user           = "amitsheokand";
  sharedFiles     = import ../shared/files.nix { inherit config pkgs; };
  additionalFiles = import ./files.nix { inherit user config pkgs; };
  mlxModel = "/Users/${user}/models/DeepSeek-V4-Pro-Qwen3.5-9B-4bit";
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
    # Existing files (gh config.yml, etc.) get renamed instead of aborting switch.
    backupFileExtension = "hm-backup";
    users.${user} = { pkgs, config, lib, ... }:
      let
        headroom = import ../shared/headroom.nix { inherit pkgs lib; };
        commandCode = import ../shared/command-code.nix { inherit pkgs lib; };
        # Desktop catalog over LAN. Default stays MLX; `/model forge` hits PC.
        hipfireLan = import ../shared/pi-hipfire-catalog.nix {
          inherit lib;
          baseUrl = "http://nixos.local:8080/v1";
        };
        piAgent = import ../shared/pi-agent.nix {
          inherit pkgs lib;
          pi = llm-agents-nix.packages.${pkgs.stdenv.hostPlatform.system}.pi;
          localSettings = {
            model = mlxModel;
            defaultProvider = "mlx-local";
            defaultModel = mlxModel;
            defaultThinkingLevel = "off";
          };
          localModels = {
            providerId = "mlx-local";
            apiModel = mlxModel;
            displayName = "qwen35";
            contextWindow = 16384;
            maxTokens = 2048;
            reasoning = false;
            extraCompat = { maxTokensField = "max_tokens"; };
            extraProviders = { hipfire = hipfireLan.provider; };
          };
        };
      in
      {
        home = {
          enableNixpkgsReleaseCheck = false;
          sessionVariables = {
            AI_BASE_URL = "http://127.0.0.1:8080/v1";
            AI_MODEL = mlxModel;
            AI_CONTEXT_WINDOW = "16384";
            AI_MAX_TOKENS = "2048";
            GROK_LOCAL_MODEL = mlxModel;
            GROK_LOCAL_BASE_URL = "http://127.0.0.1:8080/v1";
          } // (piAgent.sessionVariables or {});
          sessionPath = (commandCode.home.sessionPath or [])
            ++ (headroom.home.sessionPath or []);
          packages = (pkgs.callPackage ./packages.nix {})
            ++ (headroom.home.packages or [])
            ++ (commandCode.home.packages or [])
            ++ (piAgent.home.packages or []);
          file = lib.mkMerge [
            sharedFiles
            additionalFiles
            (headroom.home.file or {})
            {
              ".codex/mlx-local.config.toml" = {
                text = ''
                  model = "${mlxModel}"
                  model_provider = "mlx-local"
                  model_context_window = 16384

                  [model_providers.mlx-local]
                  name = "qwen35"
                  base_url = "http://127.0.0.1:8080/v1"
                  wire_api = "responses"
                  requires_openai_auth = false
                '';
              };
            }
            (import ../shared/ai-tools.nix { inherit pkgs lib user; })
          ];
          activation = lib.mkMerge [
            (headroom.home.activation or {})
            (commandCode.home.activation or {})
            piAgent.activation
          ];
          stateVersion = "23.11";
        };
        programs = import ../shared/home-manager.nix { inherit config pkgs lib; };
        manual.manpages.enable = false;
      };
  };
}
