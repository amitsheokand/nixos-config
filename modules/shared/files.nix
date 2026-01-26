{ pkgs, config, ... }:

let
  githubPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKmFX/3oHUu5hbgQXWZHqL/MIpA0Fonnikunmy9+8ckM amix.sheokand@gmail.com";
in

{
  ".ssh/id_github.pub" = {
    text = githubPublicKey;
  };
}
