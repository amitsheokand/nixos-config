{
  description = "General Purpose Configuration for macOS and NixOS";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    home-manager.url = "github:nix-community/home-manager";
    agenix.url = "github:ryantm/agenix";
    claude-desktop = {
      url = "github:k3d3/claude-desktop-linux-flake";
      inputs = { 
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
    cursor = {
      url = "github:amitsheokand/cursor-nixos-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
    };
    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    # WineHQ tap for Wine on macOS
    # https://gitlab.winehq.org/wine/wine/-/wikis/MacOS
    homebrew-wine = {
      url = "github:Gcenx/homebrew-wine";
      flake = false;
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    chaotic = {
      url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = { self, darwin, claude-desktop, cursor, nix-homebrew, homebrew-bundle, homebrew-core, homebrew-cask, homebrew-wine, home-manager, nixpkgs, flake-utils, disko, agenix, chaotic } @inputs:
    let
      user = "amitsheokand";
      linuxSystems = [ "x86_64-linux" ];
      darwinSystems = [ "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs (linuxSystems ++ darwinSystems) f;
      devShell = system: let pkgs = nixpkgs.legacyPackages.${system}; in {
        default = with pkgs; mkShell {
          nativeBuildInputs = with pkgs; [ bashInteractive git age age-plugin-yubikey ];
          shellHook = with pkgs; ''
            export EDITOR=vim
          '';
        };
      };
      mkApp = scriptName: system: {
        type = "app";
        program = "${(nixpkgs.legacyPackages.${system}.writeScriptBin scriptName ''
          #!/usr/bin/env bash
          PATH=${nixpkgs.legacyPackages.${system}.git}/bin:$PATH
          echo "Running ${scriptName} for ${system}"
          exec ${self}/apps/${system}/${scriptName} "$@"
        '')}/bin/${scriptName}";
      };
      mkLinuxApps = system: {
        "apply" = mkApp "apply" system;
        "build-switch" = mkApp "build-switch" system;
        "clean" = mkApp "clean" system;
        "copy-keys" = mkApp "copy-keys" system;
        "create-keys" = mkApp "create-keys" system;
        "check-keys" = mkApp "check-keys" system;
        "disk-usage" = mkApp "disk-usage" system;
        "install" = mkApp "install" system;
        "install-with-secrets" = mkApp "install-with-secrets" system;
      };
      mkDarwinApps = system: {
        "apply" = mkApp "apply" system;
        "build" = mkApp "build" system;
        "build-switch" = mkApp "build-switch" system;
        "clean" = mkApp "clean" system;
        "copy-keys" = mkApp "copy-keys" system;
        "create-keys" = mkApp "create-keys" system;
        "check-keys" = mkApp "check-keys" system;
        "disk-usage" = mkApp "disk-usage" system;
        "rollback" = mkApp "rollback" system;
      };
    in
    {
      devShells = forAllSystems devShell;
      apps = nixpkgs.lib.genAttrs linuxSystems mkLinuxApps // nixpkgs.lib.genAttrs darwinSystems mkDarwinApps;
      darwinConfigurations = nixpkgs.lib.genAttrs darwinSystems (system:
        darwin.lib.darwinSystem {
          inherit system;
          specialArgs = inputs // { inherit user; };
          modules = [
            home-manager.darwinModules.home-manager
            nix-homebrew.darwinModules.nix-homebrew
            {
              nix-homebrew = {
                inherit user;
                enable = true;
                taps = {
                  "homebrew/homebrew-core" = homebrew-core;
                  "homebrew/homebrew-cask" = homebrew-cask;
                  "homebrew/homebrew-bundle" = homebrew-bundle;
                  # Wine tap: https://gitlab.winehq.org/wine/wine/-/wikis/MacOS
                  "gcenx/homebrew-wine" = homebrew-wine;
                };
                mutableTaps = false;
                autoMigrate = true;
              };
            }
            ./hosts/darwin
          ];
        }
      );
      nixosConfigurations = 
        # Platform-based configurations (current behavior)
        nixpkgs.lib.genAttrs linuxSystems (system:
          nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = inputs // { inherit user; };
            modules = [
              disko.nixosModules.disko
              chaotic.nixosModules.default
              agenix.nixosModules.default
              home-manager.nixosModules.home-manager {
                home-manager = {
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  users.${user} = { config, pkgs, lib, ... }:
                    import ./modules/nixos/home-manager.nix { inherit config pkgs lib inputs; };
                };
              }
              # Add Cursor IDE from flake
              ({ pkgs, ... }: {
                environment.systemPackages = [ cursor.packages.${system}.default ];
              })
              ./hosts/nixos
            ];
          }
        )
        
        // # Named host configurations
        
        {
          garfield = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = inputs // { inherit user; };
            modules = [
              disko.nixosModules.disko
              chaotic.nixosModules.default
              agenix.nixosModules.default
              home-manager.nixosModules.home-manager {
                home-manager = {
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  users.${user} = { config, pkgs, lib, ... }:
                    import ./modules/nixos/home-manager.nix { inherit config pkgs lib inputs; };
                };
              }
              # Add Cursor IDE from flake
              ({ pkgs, ... }: {
                environment.systemPackages = [ cursor.packages.x86_64-linux.default ];
              })
              ./hosts/nixos/garfield
            ];
          };
        };
    };
}
