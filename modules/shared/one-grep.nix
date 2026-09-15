# one-grep from github:amitsheokand/open-grep.
# Installs the Nix package on every host and registers MCP (stdio) so agents
# do not depend on a cargo symlink at ~/.local/bin/one-grep.
#
# Grok + Zed are not in the upstream HM module. Extra activation registers those
# and strips leftover zvec_grep HTTP entries once the binary exists.
# zvec-grep is retired: this module also uninstalls the npm CLI, git hooks, and
# index dirs so a later switch cannot revive the post-commit OOM path.
{ config, pkgs, lib, open-grep, ... }:

let
  pkg = open-grep.packages.${pkgs.stdenv.hostPlatform.system}.one-grep;
  oneGrepBin = "${pkg}/bin/one-grep";
in
{
  imports = [ open-grep.homeManagerModules.one-grep ];

  programs.one-grep = {
    enable = true;
    package = pkg;
    installPackage = true;
    command = oneGrepBin;
    checkCommand = false;
    mcp = {
      cursor.enable = true;
      opencode.enable = true;
      pi.enable = true;
      muse.enable = true;
      hermes.enable = true;
      commandCode.enable = true;
    };
  };

  home.file = {
    ".grok/rules/one-grep.md".source = ./grok-rules/one-grep.md;
    ".grok/prompts/local-helper.md".source = ./grok-prompts/local-helper.md;
  };

  home.activation.removeZvecGrep = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    echo "one-grep: removing leftover zvec-grep" >&2
    rm -f "$HOME/.local/bin/zg"
    rm -f "$HOME/.local/bin"/zg-refresh* "$HOME/.local/bin"/zg-index*
    rm -rf "$HOME/.local/lib/node_modules/@zvec/zvec-grep" \
      "$HOME/.local/lib/node_modules/@zvec"
    rm -f "$HOME/.config/systemd/user/zvec-grep.service" \
      "$HOME/.config/systemd/user/zvec-grep-refresh.service" \
      "$HOME/.config/systemd/user/default.target.wants/zvec-grep.service" \
      "$HOME/.config/systemd/user/default.target.wants/zvec-grep-refresh.service"
    rm -f "$HOME/.grok/rules/zvec-grep.md" \
      "$HOME/.cache/zvec-grep-refresh.lock" \
      "$HOME/.cache/zvec-grep-refresh.log"
    rm -f "$HOME/Library/LaunchAgents/"*zvec-grep* 2>/dev/null || true

    remove_zvec_hook() {
      local hook="$1"
      [[ -e "$hook" || -L "$hook" ]] || return 0
      local hit=0
      if [[ -L "$hook" ]]; then
        case "$(readlink "$hook" 2>/dev/null || true)" in
          *zvec-grep-post-commit*) hit=1 ;;
        esac
      fi
      if [[ "$hit" -eq 0 ]] && [[ -f "$hook" ]] && \
         grep -qE 'zvec-grep-post-commit|zg-refresh' "$hook" 2>/dev/null; then
        hit=1
      fi
      if [[ "$hit" -eq 1 ]]; then
        echo "one-grep: removing leftover git hook $hook" >&2
        rm -f "$hook"
      fi
    }
    (
      shopt -s nullglob
      for repo in "$HOME/work"/* "$HOME/work/worktrees"/* "$HOME/dev"/*; do
        [[ -d "$repo/.git/hooks" ]] || continue
        remove_zvec_hook "$repo/.git/hooks/post-commit"
        remove_zvec_hook "$repo/.git/hooks/post-commit.local"
        for leftover in "$repo/.git/hooks"/post-commit.disabled*; do
          remove_zvec_hook "$leftover"
        done
      done
      for root in "$HOME/work"/* "$HOME/work/worktrees"/* "$HOME/dev"/*; do
        if [[ -d "$root/.zvec-grep" ]]; then
          echo "one-grep: removing leftover .zvec-grep under a checkout" >&2
          rm -rf "$root/.zvec-grep"
        fi
      done
    )
  '';

  home.activation.oneGrepExtraClients = lib.hm.dag.entryAfter [ "oneGrepMcp" "removeZvecGrep" ] ''
    export ONE_GREP=${lib.escapeShellArg oneGrepBin}
    ${pkgs.python3}/bin/python3 ${./scripts/one-grep-extra-clients.py} || \
      echo "one-grep: WARNING Grok/Zed merge or zvec strip failed" >&2
  '';
}
