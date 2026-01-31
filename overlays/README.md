# Overlays

Files in this directory are automatically loaded as Nix overlays during each build. Overlays allow you to:
* Add new packages or create custom package definitions
* Override existing packages with patches, different versions, or configurations
* Create wrapper scripts and development tools
* Package AppImages and other external binaries

**Important:** All overlay files must be added to git before building (`git add <file>.nix`) since Nix flakes only see tracked files.

## How to Add an Overlay

1. Create a `.nix` file in this directory
2. Use the standard overlay format: `self: super: { ... }` or `final: prev: { ... }`
3. Run `git add overlays/<your-file>.nix`
4. Rebuild with `nix run .#build-switch`

## Common Patterns

### AppImage Wrapper with Wayland Support
```nix
self: super: with super; {
  app-name = appimageTools.wrapType2 rec {
    pname = "app-name";
    version = "1.0.0";
    src = ./app.AppImage;  # or fetchurl for remote

    nativeBuildInputs = [ makeWrapper ];

    extraInstallCommands = ''
      wrapProgram $out/bin/${pname} \
        --add-flags "--ozone-platform=wayland --enable-features=UseOzonePlatform"
    '';
  };
}
```

### NPM/Node.js Tool Wrapper
```nix
final: prev: {
  tool-name = prev.writeShellScriptBin "tool-name" ''
    export PATH="${prev.nodejs_20}/bin:$PATH"
    exec ${prev.nodejs_20}/bin/npx --yes package-name "$@"
  '';
}
```

### Package Override with Custom JDK
```nix
final: prev: {
  jetbrains = prev.jetbrains // {
    phpstorm = prev.jetbrains.phpstorm.override {
      jdk = prev.jdk21;
    };
  };
}
```

### Development Environment with Dependencies
```nix
final: prev:
let
  deps = with prev; [ lib1 lib2 lib3 ];
in {
  tool-deps = prev.buildEnv {
    name = "tool-deps";
    paths = deps;
  };

  tool-wrapper = prev.writeScriptBin "tool-wrapper" ''
    export LD_LIBRARY_PATH="${prev.lib.makeLibraryPath deps}:$LD_LIBRARY_PATH"
    exec "$@"
  '';
}
```

### Fetching from GitHub with Specific Commit
```nix
final: prev: {
  package-name = prev.package-name.overrideAttrs (old: {
    src = prev.fetchFromGitHub {
      owner = "owner";
      repo = "repo";
      rev = "commit-hash";
      sha256 = "sha256-hash";  # Use fake hash first, Nix will show correct one
    };
  });
}
```
