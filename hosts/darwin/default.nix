{ config, pkgs, codex-cli-nix, llm-agents-nix, pi, ... }:
let 
  user = "amitsheokand";
in
{
  imports = [
    ../../modules/darwin/home-manager.nix
    ../../modules/shared
  ];

  nix = {
    enable = false;
    package = pkgs.nix;
    settings = {
      trusted-users = [ "@admin" "${user}" ];
      substituters = [ "https://nix-community.cachix.org" "https://cache.nixos.org" "https://pi.cachix.org" ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "pi.cachix.org-1:lGeoGJaZ5ZDabuRzkcD5EBTNnDM4HJ1vqeOxlWk1Flk="
      ];
    };
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  environment.systemPackages =
    (import ../../modules/darwin/packages.nix { inherit pkgs; })
    ++ [
      pkgs."claude-code"
      codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
      llm-agents-nix.packages.${pkgs.stdenv.hostPlatform.system}.grok
      pi.packages.${pkgs.stdenv.hostPlatform.system}.default  # pi terminal coding agent
    ];

  # Ollama: run "ollama serve" as user Launch Agent so ollama list/run work without a terminal
  # Ref: https://www.danielcorin.com/til/nix-darwin/launch-agents/
  launchd.user.agents.ollama-serve = {
    command = "${pkgs.ollama}/bin/ollama serve";
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/tmp/ollama_${user}.out.log";
      StandardErrorPath = "/tmp/ollama_${user}.err.log";
    };
  };

  system = {
    # Turn off NIX_PATH warnings now that we're using flakes
    checks.verifyNixPath = false;
    primaryUser = user;
    stateVersion = 4;
    defaults = {
      LaunchServices = {
        LSQuarantine = false;
      };
      NSGlobalDomain = {
        AppleShowAllExtensions = true;
        ApplePressAndHoldEnabled = false;

        # 120, 90, 60, 30, 12, 6, 2
        KeyRepeat = 2;

        # 120, 94, 68, 35, 25, 15
        InitialKeyRepeat = 15;
        "com.apple.mouse.tapBehavior" = 1;
        "com.apple.sound.beep.volume" = 0.0;
        "com.apple.sound.beep.feedback" = 0;
      };
      dock = {
        autohide = false;
        show-recents = false;
        launchanim = true;
        mouse-over-hilite-stack = true;
        orientation = "left";
        tilesize = 48;
      };
      finder = {
        _FXShowPosixPathInTitle = false;
      };
      trackpad = {
        Clicking = true;
        TrackpadThreeFingerDrag = true;
      };
    };
    keyboard = {
      enableKeyMapping = true;
    };
  };
}
