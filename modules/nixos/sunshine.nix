# Sunshine: self-hosted game-stream HOST for this machine.
# Pairs with Moonlight clients (e.g. the Mac) to stream this GNOME desktop over LAN.
#
# First-time setup after `nix run .#build-switch` + relogin:
#   1. Open the web UI on this host:  https://localhost:47990  (accept the self-signed cert)
#   2. Create the admin username/password (stored locally, only used by the web UI).
#   3. On the Mac, open Moonlight → it should auto-discover "nixos" on the LAN
#      (or add it manually by IP / nixos.local). Click it → it shows a 4-digit PIN.
#   4. Back in the host web UI → "PIN" tab → enter that PIN to pair.
#   5. In Moonlight, launch the "Desktop" app to mirror this whole screen.
#
# Notes for this host (GNOME on Wayland + AMD RX 6700 XT):
#   - capSysAdmin = true grants CAP_SYS_ADMIN, required for DRM/KMS screen
#     capture under Wayland (GNOME doesn't expose wlroots capture).
#   - AMD encoding goes through VAAPI (amdgpu) automatically.
#   - networking.firewall is disabled on this host, so openFirewall is a no-op
#     but kept for correctness if the firewall is ever turned on.
{ ... }:

{
  services.sunshine = {
    enable = true;
    autoStart = true;     # start with the graphical (GNOME) session
    capSysAdmin = true;    # needed for Wayland/KMS screen capture
    openFirewall = true;   # TCP 47984/47989/47990/48010, UDP 47998-48000

    settings = {
      # Host-side ceiling: cap the negotiated bitrate regardless of what the
      # Moonlight client slider requests. Value is in kbps. This host streams
      # over a 2-hop Realtek (rtw89) Wi-Fi link, so keep desktop-sharing well
      # under the link's sustainable throughput to avoid buffer-bloat stalls.
      max_bitrate = 15000;       # 15 Mbps cap (plenty for 1080p/1440p desktop, HEVC)

      # Larger FEC budget so a brief Wi-Fi hiccup is recovered instead of
      # turning into corruption -> client drop.
      fec_percentage = 20;

      # Don't fall below this frame interval target; helps the client ride out
      # short stalls rather than tearing down the session.
      minimum_fps_target = 30;
    };
  };
}
