# one-grep — local-first hybrid workspace search (BM25 + ONNX embeddings + MCP).
# Imports the vendored Home Manager module (`one-grep-module.nix`, from
# one-grep @ 1f215f9) and points it at `pkgs.one-grep` from
# `overlays/one-grep.nix`. OSS-safe: no product names, hostnames, or absolute
# home paths — MCP config paths are the module's relative defaults.
# (A relative `path:../one-grep` flake input was rejected: `nix flake lock`
# absolutizes it into flake.lock, leaking the private home path.)
#
# NOTE: `enable = false` until the binary is installable from this repo.
# one-grep has no public remote yet, so `pkgs.one-grep` builds only from the
# sibling checkout (`../one-grep`, impure). Flip to `true` once the source is
# fetchable (public remote → flake input or fetchFromGitHub for `src`).
{ pkgs }:

{
  imports = [ ./one-grep-module.nix ];

  programs.one-grep = {
    enable = false;
    package = pkgs.one-grep;
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
