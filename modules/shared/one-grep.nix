# one-grep — local-first hybrid workspace search (BM25 + ONNX embeddings + MCP).
# Imports the vendored Home Manager module (`one-grep-module.nix`, from
# one-grep @ 1f215f9) and registers one-grep with every agent harness so NixOS
# (incl. vaayu) and Darwin share one wiring instead of hand-editing
# ~/.cursor/mcp.json, ~/.pi/agent/mcp.json, etc.
#
# OSS-safe: no product names, hostnames, or absolute home paths — the command
# is derived from `config.home.homeDirectory`.
#
# Binary: one-grep is not in nixpkgs and has no public remote yet, so wiring
# targets the location the CLI's own `install` prefers, `~/.local/bin/one-grep`
# (cargo build, copy, or symlink). `pkgs.one-grep` (overlays/one-grep.nix) still
# exists for hosts that build from a sibling checkout: set `package` and
# `installPackage = true` there.
#
# `checkCommand = true` keeps activation harmless on hosts that do not have the
# binary yet: MCP entries are only written when the command is executable.
{ config, ... }:

{
  imports = [ ./one-grep-module.nix ];

  programs.one-grep = {
    enable = true;
    package = null;
    installPackage = false;
    command = "${config.home.homeDirectory}/.local/bin/one-grep";
    checkCommand = true;
    mcp = {
      cursor.enable = true;
      opencode.enable = true;
      pi.enable = true;
      muse.enable = true;
      hermes.enable = true;
      commandCode.enable = true;
    };
  };
}
