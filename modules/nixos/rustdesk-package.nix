{ pkgs }:

let
  pname = "rustdesk";
  version = "1.4.9";
  src = pkgs.fetchurl {
    url = "https://github.com/rustdesk/rustdesk/releases/download/${version}/rustdesk-${version}-x86_64.AppImage";
    hash = "sha256-eQLNYKTymBfuviZooVyaGVKsaQ6Pewe/52IP7dTighc=";
  };
  extractedAppimage = pkgs.appimageTools.extractType2 {
    inherit pname version src;
  };
  # RustDesk 1.4.9 treats every executable under /nix/store as a traditionally
  # installed application. That incorrectly locks its settings behind a custom
  # sudo helper. The optimized x86_64 comparison stores `/nix/store` as the
  # `/nix/sto` and `re` immediates, so patch only the unique, same-length first
  # immediate. This keeps the upstream binary layout, Wayland code, and codecs.
  appimageContents = pkgs.runCommand "${pname}-${version}-portable-appimage" {
    nativeBuildInputs = [ pkgs.perl ];
  } ''
    cp -a ${extractedAppimage} $out
    core=$out/usr/share/rustdesk/lib/librustdesk.so
    chmod u+w "$(dirname "$core")" "$core"
    test "$(grep -a -o '/nix/sto' "$core" | wc -l)" -eq 1
    perl -pi -e 's{/nix/sto}{/gnu/sto}g' "$core"
    ! grep -a -q '/nix/sto' "$core"
  '';
  appimage = pkgs.appimageTools.wrapAppImage {
    inherit pname version;
    src = appimageContents;
    extraPkgs = pkgs': [ pkgs'.libva ];
    profile = ''
      export LIBVA_DRIVERS_PATH=/run/opengl-driver/lib/dri
      if [ "$XDG_SESSION_TYPE" = wayland ]; then
        export RUSTDESK_FORCED_DISPLAY_SERVER=wayland
      fi
    '';
    extraInstallCommands = ''
      install -m 444 -D ${appimageContents}/rustdesk.desktop \
        $out/share/applications/rustdesk.desktop
      cp -r ${appimageContents}/usr/share/icons $out/share/
      substituteInPlace $out/share/applications/rustdesk.desktop \
        --replace-fail "Exec=usr/share/rustdesk/rustdesk" "Exec=rustdesk"
    '';
  };
  rustdeskWrapper = pkgs.writeShellScriptBin "rustdesk" ''
    set -eu

    # PCI addresses differ between the desktop and laptop, and renderD numbers
    # can change across boots. Prefer each host's stable Intel by-path link,
    # then fall back to the conventional first render node.
    render_node=""
    for candidate in \
      /dev/dri/by-path/pci-0000:0e:00.0-render \
      /dev/dri/by-path/pci-0000:00:02.0-render \
      /dev/dri/renderD128
    do
      if [ -e "$candidate" ]; then
        render_node="$candidate"
        break
      fi
    done

    if [ -z "$render_node" ]; then
      echo "rustdesk: no usable DRM render node found" >&2
      exit 1
    fi

    case "''${1-}" in
      --check-hwcodec-config|--service) ;;
      *)
        (
          sleep 2
          ${pkgs.bubblewrap}/bin/bwrap \
            --dev-bind / / \
            --dev-bind "$render_node" /dev/dri/renderD128 \
            -- ${appimage}/bin/rustdesk --check-hwcodec-config \
            >/dev/null 2>&1
        ) &
        ;;
    esac

    exec ${pkgs.bubblewrap}/bin/bwrap \
      --dev-bind / / \
      --dev-bind "$render_node" /dev/dri/renderD128 \
      -- ${appimage}/bin/rustdesk "$@"
  '';
in
pkgs.symlinkJoin {
  name = "rustdesk-hwcodec-${version}";
  paths = [ appimage ];
  postBuild = ''
    rm $out/bin/rustdesk
    ln -s ${rustdeskWrapper}/bin/rustdesk $out/bin/rustdesk
  '';
}
