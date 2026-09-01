# SSH *server* host keys (not user auth — that is ssh-keys.nix).
# Pin so Mac / PC / odie skip TOFU and survive HashKnownHosts.
#
# Collect: `ssh-keyscan -4 -t ed25519 HOST.local`
# vaayu (192.168.1.18) was offline when this was written — add it later.
rec {
  knownHosts = {
    nixos = {
      extraHostNames = [ "nixos.local" "192.168.1.15" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHJzYGERgWG7b7ui9Wk2bfQdWo+WONmbCgN7jLb/XL9m";
    };
    odie = {
      extraHostNames = [ "odie.local" "192.168.1.16" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL6j2n8gWuSsCflZl00ygzGlTkfwZHc5bKOoSowJo5yp";
    };
    "ai-mac" = {
      extraHostNames = [ "ai-mac.local" "192.168.1.14" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJjFAys37P1CXBf2kmW3CloVJA0mN88pK2PPfRk/QES3";
    };
  };

  fileText =
    builtins.concatStringsSep "\n" (
      builtins.attrValues (
        builtins.mapAttrs (
          name: h:
          builtins.concatStringsSep "," ([ name ] ++ h.extraHostNames)
          + " "
          + h.publicKey
        ) knownHosts
      )
    )
    + "\n";
}
