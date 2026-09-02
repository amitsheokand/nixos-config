# Muse Code — Meta's terminal/CI coding agent (not in llm-agents.nix).
# Upstream: curl -fsSL https://dev.meta.ai/install.sh | sh
# Version from https://api.meta.ai/muse-code/channels/muse-stable
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
  version = "1.0.1-R2006.1";
  pname = "muse-code";
  artifacts = {
    x86_64-linux = {
      file = "muse-x86-linux";
      hash = "sha256-A2sbqFgroX09rfx/0ZoCVfositIwoFH3nLV0YhTpPyg=";
    };
    aarch64-linux = {
      file = "muse-aarch64-linux";
      hash = "sha256-CWGbFsC/rdojfHoQtcl9n58PHvfIjqeC3a6jHr0NnyQ=";
    };
    aarch64-darwin = {
      file = "muse-aarch64-macos";
      hash = "sha256-ucf5uttrKvGzYtMCArNm573BOzxASOkALKojbMVsVKQ=";
    };
    x86_64-darwin = {
      file = "muse-x86-macos";
      hash = "sha256-h1QIJs5tfOGLFvy7CPQex1+5GHNmeJbpPGr9LOMmYqc=";
    };
  };
  system = stdenv.hostPlatform.system;
  artifact =
    artifacts.${system}
      or (throw "muse-code: no upstream binary for ${system}");
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://lookaside.facebook.com/lookaside/muse/download/?channel=muse&version=${version}&file=${artifact.file}";
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
    install -Dm755 $src $out/libexec/muse
    makeWrapper $out/libexec/muse $out/bin/muse \
      --argv0 muse
    runHook postInstall
  '';

  meta = {
    description = "Meta Muse Code — terminal coding agent on Muse Spark";
    homepage = "https://dev.meta.ai/docs/muse-code";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "muse";
    platforms = builtins.attrNames artifacts;
  };
}
