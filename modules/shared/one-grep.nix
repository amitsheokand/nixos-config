# one-grep from github:amitsheokand/open-grep (CLI name stays `one-grep`).
# Installs the Nix package on every host and registers MCP (stdio) so agents
# do not depend on a cargo symlink at ~/.local/bin/one-grep.
#
# Grok + Zed are not in the upstream HM module. Extra activation registers those
# and strips leftover zvec_grep HTTP entries once the binary exists.
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

  home.file.".grok/rules/one-grep.md".source = ./grok-rules/one-grep.md;

  home.activation.oneGrepExtraClients = lib.hm.dag.entryAfter [ "oneGrepMcp" "installZvecGrep" ] ''
    export ONE_GREP=${lib.escapeShellArg oneGrepBin}
    ${pkgs.python3}/bin/python3 ${./scripts/one-grep-extra-clients.py} || \
      echo "one-grep: WARNING Grok/Zed merge or zvec strip failed" >&2
  '';
}
