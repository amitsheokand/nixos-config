# rgitui is not in nixpkgs or llm-agents.nix. Upstream ships GPUI binaries;
# aarch64-linux has no release yet (source build pulls Zed's GPUI tree).
{
  lib,
  stdenv,
  fetchurl,
  fetchzip,
  autoPatchelfHook,
  makeWrapper,
  undmg,
  zlib,
  libxkbcommon,
  xorg,
  wayland,
  libglvnd,
  vulkan-loader,
  fontconfig,
  freetype,
  libdrm,
  libgbm,
}:

let
  version = "0.4.0";
  pname = "rgitui";
  meta = {
    description = "GPU-accelerated Git client built with GPUI";
    homepage = "https://github.com/noahbclarkson/rgitui";
    license = lib.licenses.mit;
    platforms = [
      "x86_64-linux"
      "aarch64-darwin"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "rgitui";
  };
in
if stdenv.hostPlatform.system == "x86_64-linux" then
  stdenv.mkDerivation {
    inherit pname version meta;

    src = fetchzip {
      url = "https://github.com/noahbclarkson/rgitui/releases/download/v${version}/rgitui-${version}-x86_64-linux.tar.gz";
      hash = "sha256-7XOAYFnhH0xW7THvHOtLvfqyqJPLuxEOeU35a8K9kXY=";
    };

    nativeBuildInputs = [
      autoPatchelfHook
      makeWrapper
    ];

    buildInputs = [
      zlib
      libxkbcommon
      xorg.libxcb
      stdenv.cc.cc.lib
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin $out/share/applications
      install -Dm755 rgitui $out/bin/rgitui
      cat > $out/share/applications/rgitui.desktop <<EOF
      [Desktop Entry]
      Type=Application
      Name=rgitui
      GenericName=Git Client
      Comment=GPU-accelerated Git client built with GPUI
      Exec=rgitui %U
      Icon=rgitui
      Categories=Development;RevisionControl;
      StartupWMClass=rgitui
      Terminal=false
      EOF
      wrapProgram $out/bin/rgitui \
        --prefix LD_LIBRARY_PATH : ${
          lib.makeLibraryPath [
            wayland
            libglvnd
            vulkan-loader
            libxkbcommon
            fontconfig
            freetype
            libdrm
            libgbm
            xorg.libxcb
            xorg.libX11
          ]
        }
      runHook postInstall
    '';
  }
else if stdenv.hostPlatform.isDarwin then
  stdenv.mkDerivation {
    inherit pname version meta;

    src = fetchurl {
      url = "https://github.com/noahbclarkson/rgitui/releases/download/v${version}/rgitui-${version}-arm64-macos.dmg";
      hash = "sha256-dZPGwtrfSt3m5VYjkdrLTNRZ3031WCHNz6XK7yHNTRM=";
    };

    nativeBuildInputs = [
      undmg
      makeWrapper
    ];

    sourceRoot = ".";

    installPhase = ''
      runHook preInstall
      mkdir -p $out/Applications $out/bin
      cp -R *.app $out/Applications/
      app=$(echo $out/Applications/*.app)
      bin="$app/Contents/MacOS/rgitui"
      if [ ! -x "$bin" ]; then
        bin=$(echo "$app/Contents/MacOS/"*)
      fi
      makeWrapper "$bin" $out/bin/rgitui
      runHook postInstall
    '';
  }
else
  throw "rgitui: no upstream binary for ${stdenv.hostPlatform.system} (aarch64-linux not shipped; GPUI source build is Zed-sized)"
