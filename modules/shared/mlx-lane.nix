# Exclusive MLX lane switcher for 24 GB M4.
# Compactor (LAN compact :8081) vs Gemma coder (:8080) — never both.
{ pkgs }:

pkgs.writeShellApplication {
  name = "mlx-lane";
  text = ''
    set -euo pipefail
    uid="$(id -u)"
    domain="gui/''${uid}"
    gemma="org.nixos.mlx-lm-server"
    compact="org.nixos.mlx-lm-compact"
    plist_gemma="$HOME/Library/LaunchAgents/''${gemma}.plist"
    plist_compact="$HOME/Library/LaunchAgents/''${compact}.plist"

    stop_label() {
      launchctl bootout "''${domain}/$1" 2>/dev/null || true
    }

    start_label() {
      local label="$1" plist="$2"
      stop_label "$label"
      if [[ ! -f "$plist" ]]; then
        echo "missing $plist — run nix run .#build-switch" >&2
        exit 1
      fi
      launchctl bootstrap "$domain" "$plist"
      launchctl kickstart -k "''${domain}/''${label}"
    }

    status() {
      echo -n "compact :8081  "
      if curl -fsS --max-time 1 http://127.0.0.1:8081/v1/models >/dev/null 2>&1; then
        echo UP
      else
        echo down
      fi
      echo -n "gemma   :8080  "
      if curl -fsS --max-time 1 http://127.0.0.1:8080/v1/models >/dev/null 2>&1; then
        echo UP
      else
        echo down
      fi
    }

    case "''${1:-status}" in
      compact)
        echo "lane: compact (stop gemma)"
        stop_label "$gemma"
        start_label "$compact" "$plist_compact"
        ;;
      gemma)
        echo "lane: gemma (stop compact — LAN /compact waits)"
        stop_label "$compact"
        start_label "$gemma" "$plist_gemma"
        ;;
      status)
        status
        ;;
      *)
        echo "usage: mlx-lane compact|gemma|status" >&2
        exit 1
        ;;
    esac
  '';
}
