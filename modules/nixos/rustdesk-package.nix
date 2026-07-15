{ pkgs }:

let
  pname = "rustdesk";
  version = "1.4.9";
  igpuRenderNode = "/dev/dri/by-path/pci-0000:0e:00.0-render";
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
in
pkgs.symlinkJoin {
  name = "rustdesk-hwcodec-${version}";
  paths = [ appimage ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    rm $out/bin/rustdesk
    # RustDesk's bundled FFmpeg invokes VA-API without a device name, which
    # always selects renderD128. In a private mount namespace, map the stable
    # iGPU node onto that expected path while leaving the rest of the host
    # filesystem and devices unchanged.
    makeWrapper ${pkgs.bubblewrap}/bin/bwrap $out/bin/rustdesk \
      --run 'case "''${1-}" in --check-hwcodec-config|--service) ;; *) (sleep 2; ${pkgs.bubblewrap}/bin/bwrap --dev-bind / / --dev-bind ${igpuRenderNode} /dev/dri/renderD128 -- ${appimage}/bin/rustdesk --check-hwcodec-config >/dev/null 2>&1) & ;; esac' \
      --add-flags "--dev-bind / /" \
      --add-flags "--dev-bind ${igpuRenderNode} /dev/dri/renderD128" \
      --add-flags "--" \
      --add-flags "${appimage}/bin/rustdesk"
  '';
}
