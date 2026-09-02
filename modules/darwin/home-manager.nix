{ config, pkgs, lib, home-manager, llm-agents-nix, ... }:

let
  user           = "amitsheokand";
  sharedFiles     = import ../shared/files.nix { inherit config pkgs; };
  additionalFiles = import ./files.nix { inherit user config pkgs; };
  mlxMac = import ../shared/mlx-mac.nix { inherit user pkgs; };
  inherit (mlxMac) mlxModelPath mlxPickerName contextWindow maxTokens;
  compactPi = import ../shared/pi-compactor.nix {
    baseUrl = "http://127.0.0.1:8081/v1";
  };
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
        zvecGrep = import ../shared/zvec-grep.nix { inherit pkgs lib; };
        museSpark = import ../shared/muse-spark.nix { inherit pkgs lib; };
        # Desktop catalog over LAN. Default stays MLX; `/model forge` hits PC.
        hipfireLan = import ../shared/pi-hipfire-catalog.nix {
          inherit lib;
          baseUrl = "http://nixos.local:8080/v1";
        };
        piAgent = import ../shared/pi-agent.nix {
          inherit pkgs lib;
          pi = llm-agents-nix.packages.${pkgs.stdenv.hostPlatform.system}.pi;
          localSettings = {
            model = mlxModelPath;
            defaultProvider = "mlx-local";
            defaultModel = mlxModelPath;
            defaultThinkingLevel = "low";
          };
          localModels = {
            providerId = "mlx-local";
            apiModel = mlxModelPath;
            displayName = mlxPickerName;
            inherit contextWindow maxTokens;
            reasoning = true;
            extraCompat = { maxTokensField = "max_tokens"; };
            extraProviders = {
              hipfire = hipfireLan.provider;
              mlx-compact = compactPi.provider;
              compact = compactPi.provider;
            };
          };
        };
      in
      {
        home = {
          enableNixpkgsReleaseCheck = false;
          sessionVariables = {
            AI_BASE_URL = "http://127.0.0.1:8080/v1";
            AI_MODEL = mlxModelPath;
            AI_CONTEXT_WINDOW = toString contextWindow;
            AI_MAX_TOKENS = toString maxTokens;
            GROK_LOCAL_MODEL = mlxModelPath;
            GROK_LOCAL_BASE_URL = "http://127.0.0.1:8080/v1";
          } // compactPi.sessionVariables // (piAgent.sessionVariables or {});
          sessionPath = (commandCode.home.sessionPath or [])
            ++ (zvecGrep.home.sessionPath or [])
            ++ (headroom.home.sessionPath or []);
          packages = (pkgs.callPackage ./packages.nix {})
            ++ (headroom.home.packages or [])
            ++ (commandCode.home.packages or [])
            ++ (zvecGrep.home.packages or [])
            ++ (museSpark.home.packages or [])
            ++ (piAgent.home.packages or []);
          file = lib.mkMerge [
            sharedFiles
            additionalFiles
            (headroom.home.file or {})
            {
              ".codex/mlx-local.config.toml" = {
                text = ''
                  model = "${mlxModelPath}"
                  model_provider = "mlx-local"
                  model_context_window = ${toString contextWindow}

                  [model_providers.mlx-local]
                  name = "${mlxPickerName}"
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
            (zvecGrep.home.activation or {})
            (museSpark.home.activation or {})
            piAgent.activation
          ];
          stateVersion = "23.11";
        };
        programs = import ../shared/home-manager.nix { inherit config pkgs lib; };
        manual.manpages.enable = false;
      };
  };
}
