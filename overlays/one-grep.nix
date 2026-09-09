# one-grep overlay: exposes `pkgs.one-grep` (vendored, see
# `modules/shared/one-grep-package.nix` for the source tip). Auto-applied via
# `modules/shared/default.nix` on every host.
final: prev: {
  one-grep = final.callPackage ../modules/shared/one-grep-package.nix { };
}
