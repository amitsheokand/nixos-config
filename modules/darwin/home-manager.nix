{ config, pkgs, lib, home-manager, ... }:

let
  user           = "amitsheokand";
  sharedFiles     = import ../shared/files.nix { inherit config pkgs; };
  additionalFiles = import ./files.nix { inherit user config pkgs; };
  mlxModel = "/Users/${user}/models/DeepSeek-V4-Pro-Qwen3.5-9B-4bit";
  piModels = import ../shared/pi-local-models.nix {
    inherit pkgs;
    providerId = "mlx-local";
    apiModel = mlxModel;
    displayName = "qwen35";
    contextWindow = 65536;
    maxTokens = 4096;
  };
  piSettings = pkgs.writeText "pi-settings.json" (builtins.toJSON {
    model = mlxModel;
    defaultProvider = "mlx-local";
    defaultModel = mlxModel;
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
        home = {
          enableNixpkgsReleaseCheck = false;
          sessionVariables = {
            AI_BASE_URL = "http://127.0.0.1:8080/v1";
            AI_MODEL = mlxModel;
            AI_CONTEXT_WINDOW = "65536";
            AI_MAX_TOKENS = "4096";
            GROK_LOCAL_MODEL = mlxModel;
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
                  model = "${mlxModel}"
                  model_provider = "mlx-local"
                  model_context_window = 65536

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
            {
              syncPiModels = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                mkdir -p "$HOME/.pi/agent"
                install -m 0600 ${piModels} "$HOME/.pi/agent/models.json"
              '';
              syncPiSettings = lib.hm.dag.entryAfter [ "syncPiModels" ] ''
                mkdir -p "$HOME/.pi/agent"
                settings="$HOME/.pi/agent/settings.json"
                tmp="$(mktemp "$settings.tmp.XXXXXX")"
                trap 'rm -f "$tmp"' EXIT
                if [[ -f "$settings" ]]; then
                  ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$settings" ${piSettings} > "$tmp"
                else
                  ${pkgs.jq}/bin/jq '.' ${piSettings} > "$tmp"
                fi
                chmod 0600 "$tmp"
                if [[ ! -f "$settings" ]] || ! cmp -s "$tmp" "$settings"; then
                  mv "$tmp" "$settings"
                fi
                chmod 0600 "$settings"
              '';
            }
          ];
          stateVersion = "23.11";
        };
        programs = import ../shared/home-manager.nix { inherit config pkgs lib; };
        manual.manpages.enable = false;
      };
  };
}
