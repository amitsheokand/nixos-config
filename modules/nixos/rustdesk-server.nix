# RustDesk self-hosted server (ID + relay) for local network.
# See: https://wiki.nixos.org/wiki/RustDesk
#
# On Mac (and this NixOS machine): install RustDesk, then in the client:
#   Burger menu → Network →
#   ID/Relay Server: <this host> (e.g. nixos, nixos.local, or this machine's IP)
#   Key: paste contents of /var/lib/private/rustdesk/id_ed25519.pub (on this NixOS host)
#
{ config, lib, ... }:

{
  services.rustdesk-server = {
    enable = true;
    openFirewall = true;
    # This host is the server; clients use this hostname (or IP) as ID/Relay server.
    signal.relayHosts = [ config.networking.hostName ];
  };
}
