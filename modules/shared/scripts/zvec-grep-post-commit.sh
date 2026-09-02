#!/bin/sh
# Managed by nix home-manager (zvec-grep.nix). Incremental index after commit.
set -eu

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
case "$root" in
  "$HOME/work/advait"|"$HOME/work/advait-docs")
    zg-refresh-advait --repo "$root" --background
    ;;
esac

hook_dir=$(dirname "$0")
if [ -x "$hook_dir/post-commit.local" ]; then
  exec "$hook_dir/post-commit.local" "$@"
fi
