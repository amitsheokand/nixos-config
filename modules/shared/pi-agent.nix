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
    "npm:pi-cc-compact@0.1.0"
    "npm:pi-cursor-sdk@0.2.0"
    # Load FFF before pi-tool-display. Override re-registers grep/find;
    # display 0.5.0 skips those names only if FFF already owns them.
    # Replaces Pi rg/fd grep+find (limit 100, --json, --hidden) with FFF:
    # grouped pages + cursor, frecency, no rg subprocess.
    "npm:@ff-labs/pi-fff@0.10.5"
    "npm:pi-tool-display@0.5.0"
  ];

  sharedSettings = {
    inherit packages;
    theme = "light/dark";
    hideThinkingBlock = false;
    quietStartup = true;
    defaultThinkingLevel = "high";
    # Pi auto-compacts when tokens > contextWindow - reserveTokens.
    # reserve must stay < 0.2 * smallest advertised window (feather 32k)
    # so pi-async-compaction has a non-empty start window at START_RATIO=0.6.
    compaction = {
      enabled = true;
      reserveTokens = 4096;
      keepRecentTokens = 12000;
    };
    # So `pi install` / activation works without a global npm on PATH.
    npmCommand = [ "${nodejs}/bin/npm" ];
  } // localSettings;

  settingsFile = pkgs.writeText "pi-shared-settings.json" (builtins.toJSON sharedSettings);
  hermesMemoryConfig = ./pi-hermes-memory-config.json;
  standingInstructions = ./pi-standing.md;

  modelsFile =
    if localModels == null then null
    else import ./pi-local-models.nix ({ inherit pkgs; } // localModels);

  # Declarative Pi extensions (OpenRouter ox-alpha, …). Key stays in
  # ~/.config/openrouter.env (sourced by zsh); never commit secrets here.
  piExtensions = [
    ./pi-extensions/openrouter-ox-alpha.ts
  ];

  syncPiExtensions = lib.concatMapStrings (ext: ''
    install -m 0644 ${ext} "$HOME/.pi/agent/extensions/$(basename ${ext})"
  '') piExtensions;

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

  # Keep the pi↔Cursor tool bridge on for every login. Default is already on
  # in pi-cursor-sdk; this blocks PI_CURSOR_PI_TOOL_BRIDGE=0 leaking in from
  # smoke scripts or a one-off shell.
  sessionVariables = {
    PI_CURSOR_PI_TOOL_BRIDGE = "1";
    # Background compact from 60% of the advertised window; hard compact at
    # window - reserveTokens. Default 0.8 is too late on a 48k honest window.
    PI_ASYNC_PREFIX_COMPACTION_START_RATIO = "0.6";
    # Chasen Liao 2026-08-27: built-in grep is rg --json, limit 100, 50KB
    # truncations; TODO-class queries dump the page. FFF override paginates.
    PI_FFF_MODE = "override";
    # Home trees here include nix store, models, and worktrees.
    FFF_ENABLE_HOME_SCAN = "0";
  };

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

      syncPiExtensions = lib.hm.dag.entryAfter [ "syncPiSettings" ] ''
        mkdir -p "$HOME/.pi/agent/extensions"
        ${syncPiExtensions}
      '';

      # pi-tool-display 0.5.0 re-registers grep/find even when FFF already owns
      # them (tryGetAllTools is empty during extension load). Leave FFF as the
      # owner; display still wraps read/ls/bash/edit/write.
      syncPiToolDisplayOwnership = lib.hm.dag.entryAfter [ "syncPiExtensions" ] ''
        cfg="$HOME/.pi/agent/extensions/pi-tool-display/config.json"
        mkdir -p "$(dirname "$cfg")"
        tmp="$(mktemp "$cfg.tmp.XXXXXX")"
        trap 'rm -f "$tmp"' EXIT
        if [[ -f "$cfg" ]]; then
          ${pkgs.jq}/bin/jq \
            '.registerToolOverrides.grep = false | .registerToolOverrides.find = false' \
            "$cfg" > "$tmp"
        else
          ${pkgs.jq}/bin/jq -n \
            '{registerToolOverrides: {grep: false, find: false}}' > "$tmp"
        fi
        chmod 0600 "$tmp"
        if [[ ! -f "$cfg" ]] || ! cmp -s "$tmp" "$cfg"; then
          mv "$tmp" "$cfg"
        fi
      '';

      # policy-only hermes: compact policy, no MEMORY.md injection, flush via
      # GPT-5.6 Luna so compact does not spawn a second job on the desktop GPU.
      syncHermesMemory = lib.hm.dag.entryAfter [ "syncPiSettings" ] ''
        mkdir -p "$HOME/.pi/agent/pi-hermes-memory"
        install -m 0600 ${hermesMemoryConfig} "$HOME/.pi/agent/hermes-memory-config.json"
        standing="$HOME/.pi/agent/pi-hermes-memory/STANDING.md"
        if [[ ! -f "$standing" ]]; then
          install -m 0600 ${standingInstructions} "$standing"
        fi
      '';

      # Cursor CLI wraps `git commit` and appends Co-authored-by when this is
      # true. Keep it off so agent commits stay unsigned by Cursor.
      syncCursorCliAttribution = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        cfg="$HOME/.cursor/cli-config.json"
        if [[ -f "$cfg" ]]; then
          tmp="$(mktemp "$cfg.tmp.XXXXXX")"
          trap 'rm -f "$tmp"' EXIT
          ${pkgs.jq}/bin/jq '.attribution.attributeCommitsToAgent = false' "$cfg" > "$tmp"
          chmod 0600 "$tmp"
          if ! cmp -s "$tmp" "$cfg"; then
            mv "$tmp" "$cfg"
          fi
        fi
      '';
    };
}
