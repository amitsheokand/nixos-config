# Prime Agent — pinned release tarballs wrapped for NixOS/Darwin.
# Upstream has no flake; public installs are npm package tarballs from GitHub Releases.
# Sibling @earendil-works/* packages are vendored as directories (avoids nested R2 URLs).
{
  lib,
  stdenvNoCC,
  buildNpmPackage,
  fetchurl,
  makeWrapper,
  nodejs_22,
  gitMinimal,
  openssh,
  ripgrep,
  fd,
}:

let
  version = "0.7.0";
  nodejs = nodejs_22;

  fetchReleaseTarball =
    name: hash:
    fetchurl {
      url = "https://github.com/PrimeIntellect-ai/prime-agent/releases/download/v${version}/${name}-${version}.tgz";
      inherit hash;
    };

  mainTarball = fetchReleaseTarball "prime-agent" "sha256-iLZXhRjHLNUaglvIDyjg/vmmTGfeSn1v16/Xyhs02gs=";
  aiTarball = fetchReleaseTarball "prime-agent-ai" "sha256-fNuz6DX0jdEDMl96NRzlQLJ69NFhrrnHub3MEv55Ca8=";
  coreTarball = fetchReleaseTarball "prime-agent-core" "sha256-AxM3MImDHZos4G6HT6uLnAV2LACU/5/CApCM99t/mc0=";
  tuiTarball = fetchReleaseTarball "prime-agent-tui" "sha256-MiX3+S6H24D+LJAF0fd3BzWuYlwyk17yKDaI/JvTOVE=";

  src = stdenvNoCC.mkDerivation {
    name = "prime-agent-${version}-src";
    preferLocalBuild = true;
    allowSubstitutes = false;
    nativeBuildInputs = [ nodejs ];

    buildCommand = ''
      mkdir -p $out/vendor/prime-agent-ai $out/vendor/prime-agent-core $out/vendor/prime-agent-tui
      tar -xzf ${mainTarball} -C $out --strip-components=1
      tar -xzf ${aiTarball} -C $out/vendor/prime-agent-ai --strip-components=1
      tar -xzf ${coreTarball} -C $out/vendor/prime-agent-core --strip-components=1
      tar -xzf ${tuiTarball} -C $out/vendor/prime-agent-tui --strip-components=1
      cp ${./package-lock.json} $out/package-lock.json

      ${nodejs}/bin/node <<'EOF'
      const fs = require("fs");
      const path = require("path");
      const out = process.env.out;

      const rootPath = path.join(out, "package.json");
      const root = JSON.parse(fs.readFileSync(rootPath, "utf8"));
      root.dependencies["@earendil-works/pi-agent-core"] = "file:vendor/prime-agent-core";
      root.dependencies["@earendil-works/pi-ai"] = "file:vendor/prime-agent-ai";
      root.dependencies["@earendil-works/pi-tui"] = "file:vendor/prime-agent-tui";
      fs.writeFileSync(rootPath, JSON.stringify(root, null, 2) + "\n");

      const corePath = path.join(out, "vendor/prime-agent-core/package.json");
      const core = JSON.parse(fs.readFileSync(corePath, "utf8"));
      core.dependencies["@earendil-works/pi-ai"] = "file:../prime-agent-ai";
      fs.writeFileSync(corePath, JSON.stringify(core, null, 2) + "\n");
      EOF
    '';
  };

  runtimeBins = lib.makeBinPath [
    nodejs
    gitMinimal
    openssh
    ripgrep
    fd
  ];
in
buildNpmPackage {
  pname = "prime-agent";
  inherit version src;

  npmDepsHash = "sha256-pL4xadnnp2ZTAX3DPgl79ehHpfFC6ZeS+TKtlIxRWqE=";

  # Release artifact is already built; zeromq ships platform prebuilds.
  dontNpmBuild = true;
  dontNpmPrune = true;
  npmRebuild = false;
  makeCacheWritable = true;
  # Stripping corrupts prebuilt native addons (zeromq/koffi).
  dontStrip = true;

  npmInstallFlags = [
    "--omit=dev"
    "--ignore-scripts"
  ];

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    pkg="$out/lib/node_modules/prime-agent"
    ear="$pkg/node_modules/@earendil-works"

    # npm leaves file: deps as relative symlinks into missing vendor/; materialize them.
    rm -rf "$ear/pi-ai" "$ear/pi-tui" "$ear/pi-agent-core"
    mkdir -p "$ear"
    cp -a "${src}/vendor/prime-agent-ai" "$ear/pi-ai"
    cp -a "${src}/vendor/prime-agent-tui" "$ear/pi-tui"
    cp -a "${src}/vendor/prime-agent-core" "$ear/pi-agent-core"
    chmod -R u+w "$ear"

    mkdir -p "$ear/pi-agent-core/node_modules/@earendil-works"
    rm -rf "$ear/pi-agent-core/node_modules/@earendil-works/pi-ai"
    ln -s ../../../pi-ai "$ear/pi-agent-core/node_modules/@earendil-works/pi-ai"

    # Optional bin from pi-ai is not shipped in the release layout.
    rm -f "$pkg/node_modules/.bin/pi-ai"

    rm -f "$out/bin/prime-agent"
    makeWrapper ${nodejs}/bin/node "$out/bin/prime-agent" \
      --add-flags "$pkg/dist/bundle/cli.js" \
      --prefix NODE_PATH : "$out/lib/node_modules" \
      --suffix PATH : "${runtimeBins}"
  '';

  meta = {
    description = "Prime Agent — self-improving RLM coding agent";
    homepage = "https://github.com/PrimeIntellect-ai/prime-agent";
    license = lib.licenses.mit;
    mainProgram = "prime-agent";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
}
