{ pkgs }:

pkgs.stdenv.mkDerivation rec {
  pname = "grok-bot";
  version = "0.20.0";

  src = pkgs.fetchurl {
    url = "https://downloads.cursor.com/grokbot/stable/ca2c2b6f79b6130a4822d8189711b0f79f9d4661/linux/x64/Grok_Bot_${version}.deb";
    hash = "sha256-Z6brYWSrIzpcXU1QZl762iy6rp8i763oXpNKZf37sg0=";
  };

  nativeBuildInputs = with pkgs; [
    dpkg
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = with pkgs; [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libgbm
    libGL
    libnotify
    libsecret
    libuuid
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    libxshmfence
    libxscrnsaver
    libxtst
    nspr
    nss
    pango
    stdenv.cc.cc
    vulkan-loader
  ];

  # libudev comes from systemd; keep it as a runtime dep so autoPatchelf can resolve it
  # without pulling systemd into the closure as a full build input.
  runtimeDependencies = with pkgs; [
    (lib.getLib systemd)
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/opt $out/bin $out/share
    cp -a "opt/Grok Bot" $out/opt/grok-bot
    cp -a usr/share/{applications,icons} $out/share

    # Setuid chrome-sandbox is unusable on NixOS; drop the bit and disable sandbox.
    chmod 755 $out/opt/grok-bot/chrome-sandbox

    # 0.20.0 ships grok-bot.desktop directly; rewrite its absolute launcher path.
    substituteInPlace $out/share/applications/grok-bot.desktop \
      --replace-fail '"/opt/Grok Bot/grok-bot" %U' 'grok-bot %U'

    makeWrapper $out/opt/grok-bot/grok-bot $out/bin/grok-bot \
      --prefix LD_LIBRARY_PATH : ${
        pkgs.lib.makeLibraryPath (
          with pkgs;
          [
            libGL
            vulkan-loader
          ]
        )
      } \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}" \
      --add-flags "--no-sandbox" \
      --add-flags "--disable-gpu-sandbox"

    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "Grok Bot desktop agent";
    homepage = "https://x.ai/bot";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "grok-bot";
  };
}
