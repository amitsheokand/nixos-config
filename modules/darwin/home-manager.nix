{ config, pkgs, lib, home-manager, ... }:

let
  user           = "amitsheokand";
  sharedFiles     = import ../shared/files.nix { inherit config pkgs; };
  additionalFiles = import ./files.nix { inherit user config pkgs; };
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
          packages = (pkgs.callPackage ./packages.nix {})
            ++ (headroom.home.packages or []);
          file = lib.mkMerge [
            sharedFiles
            additionalFiles
            (headroom.home.file or {})
          ];
          activation = headroom.home.activation or {};
          stateVersion = "23.11";
        };
        programs = {} // import ../shared/home-manager.nix { inherit config pkgs lib; };
        manual.manpages.enable = false;
      };
  };
}
