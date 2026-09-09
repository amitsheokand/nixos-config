# Exclusive MLX lane switcher for 24 GB M4.
#
# MiniCPM5-2B longctx (:8080, login-resident) can share RAM with Compactor
# (:8081). Gemma 12B coder (:8080, on demand) is exclusive — stop MiniCPM
# and compact first.
{ pkgs }:

pkgs.writeShellApplication {
  name = "mlx-lane";
  text = ''
    set -euo pipefail
    uid="$(id -u)"
    domain="gui/''${uid}"
    minicpm="org.nixos.mlx-lm-minicpm"
    gemma="org.nixos.mlx-lm-server"
    compact="org.nixos.mlx-lm-compact"
    plist_minicpm="$HOME/Library/LaunchAgents/''${minicpm}.plist"
    plist_gemma="$HOME/Library/LaunchAgents/''${gemma}.plist"
    plist_compact="$HOME/Library/LaunchAgents/''${compact}.plist"

    stop_label() {
      launchctl bootout "''${domain}/$1" 2>/dev/null || true
    }

    is_loaded() {
      launchctl print "''${domain}/$1" >/dev/null 2>&1
    }

    is_running() {
      launchctl print "''${domain}/$1" 2>/dev/null | grep -q '^	state = running$'
    }

    http_up() {
      curl -fsS --max-time 2 "http://127.0.0.1:$1/v1/models" >/dev/null 2>&1
    }

    ensure_label() {
      local label="$1" plist="$2"
      if [[ ! -f "$plist" ]]; then
        echo "missing $plist — run nix run .#build-switch" >&2
        exit 1
      fi
      if ! is_loaded "$label"; then
        launchctl bootstrap "$domain" "$plist"
      fi
      if ! is_running "$label"; then
        launchctl kickstart "''${domain}/''${label}"
      fi
    }

    lane_status() {
      local name="$1" port="$2" label="$3" log="$4"
      printf '%s :%s  ' "$name" "$port"
      if http_up "$port" && is_running "$label"; then
        echo UP
      elif http_up "$port"; then
        echo "UP (other process on :$port)"
      elif is_running "$label"; then
        echo "starting — $log"
      else
        echo down
      fi
    }

    case "''${1:-status}" in
      minicpm|longctx)
        echo "lane: minicpm longctx (stop gemma; compact may stay)"
        stop_label "$gemma"
        if http_up 8080 && is_running "$minicpm"; then
          echo "minicpm already UP"
          exit 0
        fi
        if is_running "$minicpm"; then
          echo "minicpm already running (load). log: /tmp/mlx-lm-minicpm_amitsheokand.err.log"
          exit 0
        fi
        ensure_label "$minicpm" "$plist_minicpm"
        ;;
      compact)
        echo "lane: compact (stop gemma; minicpm may stay)"
        stop_label "$gemma"
        if http_up 8081; then
          echo "compact already UP"
          exit 0
        fi
        if is_running "$compact"; then
          echo "compact already running (convert/load). do not restart. log: /tmp/mlx-lm-compact_amitsheokand.err.log"
          exit 0
        fi
        ensure_label "$compact" "$plist_compact"
        ;;
      gemma)
        echo "lane: gemma (stop minicpm + compact — LAN /compact and longctx wait)"
        stop_label "$minicpm"
        stop_label "$compact"
        if http_up 8080; then
          echo "gemma already UP"
          exit 0
        fi
        if is_running "$gemma"; then
          echo "gemma already running (load). log: /tmp/mlx-lm_amitsheokand.err.log"
          exit 0
        fi
        ensure_label "$gemma" "$plist_gemma"
        ;;
      status)
        lane_status minicpm 8080 "$minicpm" /tmp/mlx-lm-minicpm_amitsheokand.err.log
        lane_status compact 8081 "$compact" /tmp/mlx-lm-compact_amitsheokand.err.log
        lane_status gemma 8080 "$gemma" /tmp/mlx-lm_amitsheokand.err.log
        ;;
      *)
        echo "usage: mlx-lane minicpm|longctx|compact|gemma|status" >&2
        exit 1
        ;;
    esac
  '';
}
