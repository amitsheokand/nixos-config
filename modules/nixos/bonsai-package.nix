{ pkgs }:

pkgs.stdenv.mkDerivation {
  pname = "bonsai-llama-vulkan";
  version = "9591-62061f9";

  src = pkgs.fetchurl {
    url = "https://github.com/PrismML-Eng/llama.cpp/releases/download/prism-b9591-62061f9/llama-prism-b9591-62061f9-bin-ubuntu-vulkan-x64.tar.gz";
    hash = "sha256-4Chbx9fy+u4Cyu0s11kganwRtJgCIm729inXbSM3yjs=";
  };

  nativeBuildInputs = [ pkgs.autoPatchelfHook ];
  buildInputs = with pkgs; [
    openssl
    stdenv.cc.cc.lib
    vulkan-loader
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp -a ./* $out/bin/
    runHook postInstall
  '';

  meta = {
    description = "PrismML llama.cpp fork with Bonsai ternary Vulkan kernels";
    homepage = "https://github.com/PrismML-Eng/llama.cpp";
    license = pkgs.lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
