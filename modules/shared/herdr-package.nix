# Herdr 0.9 official binaries. nixpkgs is still on 0.8; multi-machine
# (`herdr machine add`, one TUI over SSH) needs 0.9.
# Upstream: https://github.com/herdrdev/herdr/releases/tag/v0.9.0
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  zlib,
  openssl,
}:

let
  version = "0.9.0";
  pname = "herdr";
  artifacts = {
    x86_64-linux = {
      file = "herdr-linux-x86_64";
      hash = "sha256-T6GgEVjdgEPaktMbJweAsNzBBgMDjZthysTYGrY/tx8=";
    };
    aarch64-linux = {
      file = "herdr-linux-aarch64";
      hash = "sha256-nI2yD7fnQnsTjVNnET8WIf/TGfL2XW8AniWUApEV8NI=";
    };
    aarch64-darwin = {
      file = "herdr-macos-aarch64";
      hash = "sha256-MrU98JhyYoBZx4mmnwKmuOKeFN3yZxFCHzRj9wwa7xc=";
    };
    x86_64-darwin = {
      file = "herdr-macos-x86_64";
      hash = "sha256-0MkgsqEmp0gJ+hSRQRyaCXpEeGysnCylG4GKmVWBzxY=";
    };
  };
  system = stdenv.hostPlatform.system;
  artifact =
    artifacts.${system}
      or (throw "herdr: no upstream binary for ${system}");
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://github.com/herdrdev/herdr/releases/download/v${version}/${artifact.file}";
    inherit (artifact) hash;
  };

  dontUnpack = true;
  dontStrip = true;

  nativeBuildInputs = [ makeWrapper ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    zlib
    openssl
    stdenv.cc.cc
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -Dm755 $src $out/libexec/herdr
    makeWrapper $out/libexec/herdr $out/bin/herdr \
      --argv0 herdr
    runHook postInstall
  '';

  meta = {
    description = "Agent multiplexer with persistent panes and multi-machine SSH attach";
    homepage = "https://herdr.dev";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "herdr";
    platforms = builtins.attrNames artifacts;
  };
}
