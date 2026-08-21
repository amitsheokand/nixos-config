# Command Code (npm: command-code → `cmd`) — not in nixpkgs yet.
# Installs into ~/.local via npm on Home Manager activation.
{ pkgs, lib, ... }:

let
  nodejs = pkgs.nodejs_22;
  npm = "${nodejs}/bin/npm";
in
{
  home.packages = [ nodejs ];

  home.sessionPath = [ "$HOME/.local/bin" ];

  home.activation.installCommandCode = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="${nodejs}/bin:$PATH"
    mkdir -p "$HOME/.local"
    if ! command -v cmd >/dev/null 2>&1 || ! npm list -g --prefix "$HOME/.local" command-code >/dev/null 2>&1; then
      echo "command-code: installing via npm into ~/.local"
      ${npm} install -g --prefix "$HOME/.local" command-code || \
        echo "command-code: WARNING npm install failed (network?)" >&2
    fi
  '';
}
