# Shared Pi coding-agent config for every host (Mac, nixos desktop, odie).
#
# Declares packages + UI prefs in ~/.pi/agent/settings.json and ensures npm
# packages are installed on Home Manager activation. Host-specific model
# defaults / models.json stay in the Darwin/NixOS home-manager callers.
#
# Auth keys (Cursor SDK, Codex, …) stay machine-local in auth.json — never
# commit those. After first login on a new machine, packages reappear via
# build-switch; paste API keys once with `pi` → `/login`.
{ pkgs, lib, pi
, localSettings ? {}
, localModels ? null  # attrset for pi-local-models.nix, or null to skip
}:

let
  nodejs = pkgs.nodejs_22;

  # Keep in sync across Mac / PC / odie. Pin versions for reproducible installs.
  packages = [
    "npm:@tintinweb/pi-subagents@0.15.0"
    "npm:@narumitw/pi-goal@0.50.0"
    "npm:pi-hermes-memory@0.9.4"
    "npm:@quintinshaw/pi-dynamic-workflows@3.5.1"
    "npm:@narumitw/pi-statusline@0.49.6"
    "npm:pi-async-compaction@0.1.7"
    "npm:pi-cursor-sdk@0.2.0"
    "npm:pi-tool-display@0.5.0"
  ];

  sharedSettings = {
    inherit packages;
    theme = "light/dark";
    hideThinkingBlock = false;
    quietStartup = true;
    defaultThinkingLevel = "high";
    # So `pi install` / activation works without a global npm on PATH.
    npmCommand = [ "${nodejs}/bin/npm" ];
  } // localSettings;

  settingsFile = pkgs.writeText "pi-shared-settings.json" (builtins.toJSON sharedSettings);

  modelsFile =
    if localModels == null then null
    else import ./pi-local-models.nix ({ inherit pkgs; } // localModels);

  # npm:pi-tool-display@0.5.0 → pi-tool-display
  # npm:@narumitw/pi-statusline@0.49.6 → @narumitw/pi-statusline
  # splitString "@" on a scoped id yields [ "" "scope/name" "version" ].
  npmDirName = src:
    let s = lib.removePrefix "npm:" src;
    in if lib.hasPrefix "@" s
       then "@${lib.elemAt (lib.splitString "@" s) 1}"
       else builtins.head (lib.splitString "@" s);

  ensurePackage = src:
    let dir = npmDirName src;
    in ''
      if [[ ! -d "$HOME/.pi/agent/npm/node_modules/${dir}" ]]; then
        echo "pi-agent: installing ${src}"
        ${lib.getExe pi} install ${lib.escapeShellArg src} || \
          echo "pi-agent: WARNING failed to install ${src} (network?)" >&2
      fi
    '';
in
{
  home.packages = [ nodejs ];

  activation =
    (lib.optionalAttrs (modelsFile != null) {
      syncPiModels = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "$HOME/.pi/agent"
        install -m 0600 ${modelsFile} "$HOME/.pi/agent/models.json"
      '';
    })
    // {
      syncPiSettings = lib.hm.dag.entryAfter (
        if modelsFile != null then [ "syncPiModels" ] else [ "writeBoundary" ]
      ) ''
        mkdir -p "$HOME/.pi/agent"
        settings="$HOME/.pi/agent/settings.json"
        tmp="$(mktemp "$settings.tmp.XXXXXX")"
        trap 'rm -f "$tmp"' EXIT
        if [[ -f "$settings" ]]; then
          ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$settings" ${settingsFile} > "$tmp"
        else
          ${pkgs.jq}/bin/jq '.' ${settingsFile} > "$tmp"
        fi
        chmod 0600 "$tmp"
        if [[ ! -f "$settings" ]] || ! cmp -s "$tmp" "$settings"; then
          mv "$tmp" "$settings"
        fi
        chmod 0600 "$settings"
      '';

      syncPiPackages = lib.hm.dag.entryAfter [ "syncPiSettings" ] ''
        export PATH="${nodejs}/bin:$PATH"
        mkdir -p "$HOME/.pi/agent/npm"
        ${lib.concatMapStrings ensurePackage packages}
      '';
    };
}
