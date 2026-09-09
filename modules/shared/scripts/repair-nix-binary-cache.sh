#!/usr/bin/env bash
# Repair malformed Nix narinfo sqlite DBs. The daemon uses
# /root/.cache/nix/binary-cache-v7.sqlite; a corrupt file makes every
# substituter lookup fail, so Nix rebuilds stdenv from tinycc instead of
# downloading cache.nixos.org.
set -euo pipefail

force=0
restart_daemon=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) force=1 ;;
    --no-restart) restart_daemon=0 ;;
    *)
      echo "usage: repair-nix-binary-cache [--force] [--no-restart]" >&2
      exit 2
      ;;
  esac
  shift
done

removed=0

repair_one() {
  local db="$1"
  [[ -e "$db" || -e "${db}-wal" || -e "${db}-shm" ]] || return 0
  if [[ "$force" -eq 0 && -e "$db" ]]; then
    if sqlite3 "$db" 'PRAGMA integrity_check;' 2>/dev/null | grep -qx ok; then
      echo "repair-nix-binary-cache: ok $db"
      return 0
    fi
  fi
  echo "repair-nix-binary-cache: removing malformed $db" >&2
  rm -f "$db" "${db}-wal" "${db}-shm" "${db}.bak"
  removed=1
}

repair_one /root/.cache/nix/binary-cache-v7.sqlite
if [[ -n "${HOME:-}" ]]; then
  repair_one "$HOME/.cache/nix/binary-cache-v7.sqlite"
fi
if [[ -n "${XDG_CACHE_HOME:-}" ]]; then
  repair_one "$XDG_CACHE_HOME/nix/binary-cache-v7.sqlite"
fi

if [[ "$removed" -eq 1 && "$(id -u)" -eq 0 && "$restart_daemon" -eq 1 ]]; then
  if command -v systemctl >/dev/null 2>&1; then
    echo "repair-nix-binary-cache: restarting nix-daemon" >&2
    systemctl restart nix-daemon.service
    restart_daemon=1
  fi
fi

if [[ "$removed" -eq 0 ]]; then
  echo "repair-nix-binary-cache: nothing to repair"
fi
exit 0
