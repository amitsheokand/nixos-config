{ config, pkgs, lib, home-manager, ... }:

let
  user           = "amitsheokand";
  sharedFiles     = import ../shared/files.nix { inherit config pkgs; };
  additionalFiles = import ./files.nix { inherit user config pkgs; };
in
{
  imports = [
    ./dock
  ];

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
    
    # Homebrew taps (must match nix-homebrew.taps in flake.nix)
    taps = [
      "gcenx/wine"  # Wine for macOS: https://gitlab.winehq.org/wine/wine/-/wikis/MacOS
    ];
    
    # Homebrew casks (GUI apps)
    casks = (pkgs.callPackage ./casks.nix {}) ++ [
      # Wine - choose one:
      "wine-stable"     # Stable release
      # "wine-devel"    # Development release  
      # "wine-staging"  # Staging with experimental patches
    ];
    
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
      {
        home = {
          enableNixpkgsReleaseCheck = false;
          packages = pkgs.callPackage ./packages.nix {};
          file = lib.mkMerge [
            sharedFiles
            additionalFiles
          ];
          stateVersion = "23.11";
        };
        programs = {} // import ../shared/home-manager.nix { inherit config pkgs lib; };
        manual.manpages.enable = false;
      };
  };

  # Fully declarative dock using the latest from Nix Store
  local.dock = {
    enable   = true;
    username = user;
    entries  = [
      # System Apps
      { path = "/System/Applications/Apps.app/"; }
      { path = "/System/Applications/Mission Control.app/"; }


      # Browsers
      { path = "/Applications/Firefox.app/"; }
      
      # Terminal & Dev Tools
      { path = "/Applications/Cursor.app/"; }
      { path = "/Applications/Zed.app/"; }
      { path = "/Applications/Fork.app/"; }
      { path = "/Applications/UTM.app/"; }
      { path = "/System/Applications/System Settings.app/"; }
      
      
      # Folders
      {
        path    = "${config.users.users.${user}.home}/Downloads";
        section = "others";
        options = "--sort dateadded --view grid --display stack";
      }
    ];
  };
}
