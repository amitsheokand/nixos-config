# RustDesk self-hosted server (ID + relay) for LAN and optional WAN access.
# See: https://wiki.nixos.org/wiki/RustDesk
#
# In the RustDesk client:
#   Burger menu → Network →
#   ID/Relay Server: use the LAN hostname/IP at home, or the public DNS/DDNS name off-site
#   Key: paste contents of /var/lib/private/rustdesk/id_ed25519.pub (on this NixOS host)
#
# For WAN access, also forward RustDesk ports on the router to this host:
#   TCP 21115-21119
#   UDP 21116
#
{ config, lib, ... }:

{
  services.rustdesk-server = {
    enable = true;
    openFirewall = true;
    # Advertise the LAN hostname for home use and the current public IP for off-site use.
    # Replace the public IP with a DDNS name later if the ISP address changes.
    signal.relayHosts = [
      config.networking.hostName
      "106.219.123.220"
    ];
  };
}
