# Happier Desktop (Linux AppImage). WebKitGTK has no Screen Orientation API, so
# the RN-web UI dies on boot with:
#   Error: undefined is not an object (evaluating 'screen.orientation.type')
# Upstream: https://github.com/happier-dev/happier/issues/363
#
# Wrapper runs the user-downloaded AppImage through appimage-run (FHS) and
# LD_PRELOADs a tiny hook that injects a document-start polyfill.
{ pkgs, lib, user, ... }:

let
  preload = pkgs.runCommandCC "happier-webkit-orientation-preload" { } ''
    mkdir -p $out/lib
    $CC -shared -fPIC -o $out/lib/happier-webkit-orientation.so \
      ${./happier-webkit-orientation-preload.c} -ldl
  '';

  wrapper = pkgs.writeShellApplication {
    name = "happier-desktop";
    runtimeInputs = [ pkgs.appimage-run ];
    text = ''
      appimage="''${HAPPIER_DESKTOP_APPIMAGE:-$HOME/Applications/happier-ui-desktop-linux-x86_64.AppImage}"
      if [ ! -e "$appimage" ]; then
        echo "happier-desktop: missing AppImage at $appimage" >&2
        echo "Download the Linux x64 build from https://github.com/happier-dev/happier/releases/tag/ui-desktop-stable" >&2
        exit 1
      fi
      export LD_PRELOAD="${preload}/lib/happier-webkit-orientation.so''${LD_PRELOAD:+:$LD_PRELOAD}"
      exec appimage-run "$appimage" --no-sandbox "$@"
    '';
  };
in
{
  home.packages = [ wrapper ];

  home.file = {
    ".local/bin/happier-desktop" = {
      source = "${wrapper}/bin/happier-desktop";
      force = true;
    };
    ".local/share/applications/happier-desktop.desktop" = {
      force = true;
      text = ''
        [Desktop Entry]
        Name=Happier Desktop
        Comment=Happier desktop GUI (WebKitGTK orientation polyfill)
        Exec=/home/${user}/.local/bin/happier-desktop %U
        Icon=happier-desktop
        Terminal=false
        Type=Application
        Categories=Development;Utility;
        StartupWMClass=happier-desktop
      '';
    };
    ".local/share/applications/happier.desktop" = {
      force = true;
      text = ''
        [Desktop Entry]
        Name=Happier
        Comment=Happier desktop control panel
        Exec=/home/${user}/.local/bin/happier-desktop %U
        Icon=happier
        Terminal=false
        Type=Application
        Categories=Development;Utility;
        StartupWMClass=happier
      '';
    };
  };
}
