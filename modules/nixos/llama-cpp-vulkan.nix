{ pkgs }:

# Official llama.cpp Ubuntu Vulkan build. Qwen3.8 needs a recent release
# (DeltaNet / MTP); the flake-locked nixpkgs llama-cpp is older than that.
pkgs.stdenv.mkDerivation {
  pname = "llama-cpp-vulkan";
  version = "b10488";

  src = pkgs.fetchurl {
    url = "https://github.com/ggml-org/llama.cpp/releases/download/b10488/llama-b10488-bin-ubuntu-vulkan-x64.tar.gz";
    hash = "sha256-8YCx40cUqXi1evW6C63/rsRCoYe/nr8iQEXj3ySqBoQ=";
  };

  nativeBuildInputs = [ pkgs.autoPatchelfHook ];
  buildInputs = with pkgs; [
    openssl
    stdenv.cc.cc.lib
    vulkan-loader
    zlib
    curl
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib
    # Tarball root is llama-b10488/{bins + shared libs}.
    srcdir="."
    if [ -d llama-b10488 ]; then
      srcdir="llama-b10488"
    fi
    # Versioned SONAMEs are symlinks (libllama.so.0 -> libllama.so.0.1.2).
    # -type f would skip them and leave autoPatchelf unable to resolve deps.
    find "$srcdir" -maxdepth 1 \( -type f -o -type l \) -name 'lib*.so*' -exec cp -a {} $out/lib/ \;
    find "$srcdir" -maxdepth 1 \( -type f -o -type l \) -executable ! -name 'lib*.so*' -exec cp -a {} $out/bin/ \;
    # ggml loads backend plugins from the executable directory, not $out/lib.
    find "$srcdir" -maxdepth 1 \( -type f -o -type l \) -name 'libggml*.so*' -exec cp -a {} $out/bin/ \;
    runHook postInstall
  '';

  meta = {
    description = "Official llama.cpp Vulkan binaries (Ubuntu x64)";
    homepage = "https://github.com/ggml-org/llama.cpp";
    license = pkgs.lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "llama-server";
  };
}
