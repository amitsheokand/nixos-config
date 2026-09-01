{ pkgs, config, ... }:

{
  # Dotfiles live in platform home-manager modules.
  # LAN SSH user pubs: ssh-keys.nix. Server host keys: ssh-host-keys.nix.
  ".ssh/known_hosts.lan" = {
    text = (import ./ssh-host-keys.nix).fileText;
  };
}
