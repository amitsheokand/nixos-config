# Herdr 0.9 always-on agent mux for PC (nixos), M1 (vaayu), M4 (ai-mac).
#
# Each host runs `herdr server`. Attach locally with `herdr`, or from another
# box via `herdr machine add` (https://herdr.dev/blog/connecting-the-machines/).
# Phone/iPad: herdr-mobile-relay PWA, or SSH then `herdr`. Not Happier.
{
  pkgs,
  lib,
  user ? "amitsheokand",
}:

let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  homeDir = if isDarwin then "/Users/${user}" else "/home/${user}";
  herdr = pkgs.callPackage ./herdr-package.nix { };
  worktrunk = pkgs.worktrunk;
  bash = pkgs.bash;

  startPi = pkgs.writeShellApplication {
    name = "herdr-start-pi-in-pane";
    runtimeInputs = [ herdr pkgs.jq pkgs.coreutils pkgs.gnugrep pkgs.gawk ];
    text = builtins.readFile ./herdr-pi-worktree/start-pi.sh;
  };

  notifyIdle = pkgs.writeShellApplication {
    name = "herdr-notify-agent-idle";
    runtimeInputs = [ herdr pkgs.jq pkgs.coreutils pkgs.gnugrep pkgs.gawk ];
    text = builtins.readFile ./herdr-agent-idle/notify.sh;
  };

  plugin = pkgs.runCommand "herdr-pi-worktree-plugin" { } ''
    mkdir -p $out
    cat > $out/herdr-plugin.toml <<EOF
id = "nixos-config.pi-worktree"
name = "Pi in worktree"
version = "0.1.0"
min_herdr_version = "0.9.0"
description = "Start Pi in Herdr worktree panes"
platforms = ["linux", "macos"]

[[actions]]
id = "start"
title = "Start Pi in pane"
contexts = ["workspace", "pane"]
command = ["${lib.getExe startPi}"]

[[events]]
on = "worktree.created"
command = ["${lib.getExe startPi}"]
EOF
  '';

  idlePlugin = pkgs.runCommand "herdr-agent-idle-plugin" { } ''
    mkdir -p $out
    cat > $out/herdr-plugin.toml <<EOF
id = "nixos-config.agent-idle"
name = "Agent idle callback"
version = "0.1.0"
min_herdr_version = "0.9.0"
description = "Notify the coordinator when a named Herdr agent settles"
platforms = ["linux", "macos"]

[[events]]
on = "pane.agent_status_changed"
command = ["${lib.getExe notifyIdle}"]
EOF
  '';

  configToml = ''
    # Managed by modules/shared/herdr.nix. Skip first-run onboarding.
    onboarding = false

    [update]
    version_check = false
    manifest_check = true

    [session]
    resume_agents_on_restore = true

    [server]
    headless_cols = 160
    headless_rows = 50

    [terminal]
    shell_mode = "auto"
    new_cwd = "follow"

    [ui]
    window_title = "{hostname}: {workspace}"

    [ui.sidebar.agents]
    row_gap = 0
    rows = [
      ["state_icon", "machine", "workspace", "tab"],
      ["agent"],
    ]

    [keys]
    new_worktree = ""
    open_worktree = ""
    remove_worktree = ""

    [[keys.command]]
    key = "prefix+shift+g"
    type = "plugin_action"
    command = "disintegrator.trunkr.create"
    description = "create worktree (worktrunk)"

    [[keys.command]]
    key = "prefix+shift+o"
    type = "plugin_action"
    command = "disintegrator.trunkr.open"
    description = "open worktree (worktrunk)"

    [[keys.command]]
    key = "prefix+shift+m"
    type = "plugin_action"
    command = "disintegrator.trunkr.merge"
    description = "merge worktree (worktrunk)"

    [[keys.command]]
    key = "prefix+d"
    type = "plugin_action"
    command = "disintegrator.trunkr.remove"
    description = "remove worktree (worktrunk)"

    [[keys.command]]
    key = "prefix+shift+i"
    type = "plugin_action"
    command = "nixos-config.pi-worktree.start"
    description = "start Pi in focused pane"
  '';

  worktrunkToml = ''
    # Managed by modules/shared/herdr.nix.
    # Create/open/merge/remove go through the trunkr Herdr plugin (`wt` +
    # `herdr worktree open`) so worktrunk hooks still run.
  '';

  agentPath = lib.concatStringsSep ":" (
    [
      "${herdr}/bin"
      "${worktrunk}/bin"
      "${pkgs.git}/bin"
      "${pkgs.fzf}/bin"
      "${pkgs.jq}/bin"
      "${pkgs.go}/bin"
      "${lib.getBin pkgs.stdenv.cc}/bin"
      "${pkgs.coreutils}/bin"
      "${pkgs.gnugrep}/bin"
      "${pkgs.gawk}/bin"
      "${bash}/bin"
      "${pkgs.zsh}/bin"
      "${homeDir}/.local/bin"
      "${homeDir}/.nix-profile/bin"
    ]
    ++ lib.optionals isDarwin [
      "/run/current-system/sw/bin"
      "/opt/homebrew/bin"
      "/usr/bin"
      "/bin"
    ]
    ++ lib.optionals (!isDarwin) [
      "/run/current-system/sw/bin"
      "/etc/profiles/per-user/${user}/bin"
      "/usr/bin"
      "/bin"
    ]
  );

  serve = pkgs.writeShellApplication {
    name = "herdr-serve";
    runtimeInputs = [ herdr pkgs.coreutils ];
    text = ''
      set -euo pipefail
      herdr_bin="${lib.getExe herdr}"
      is_up() {
        "$herdr_bin" status server >/dev/null 2>&1
      }
      if is_up; then
        echo "herdr-serve: server already running; waiting to take over" >&2
        while is_up; do
          sleep 10
        done
      fi
      exec "$herdr_bin" server
    '';
  };

  lan = pkgs.writeShellApplication {
    name = "herdr-lan";
    runtimeInputs = [ herdr pkgs.coreutils pkgs.jq ];
    text = ''
      set -euo pipefail
      herdr_bin="${lib.getExe herdr}"
      this="$(uname -n)"
      this="''${this%%.*}"

      declare -a hosts=(nixos vaayu ai-mac)
      declare -A labels=([nixos]=PC [vaayu]=M1 [ai-mac]=M4)

      echo "Herdr 0.9 LAN machines  https://herdr.dev/blog/connecting-the-machines/"
      echo "Local is this host ($this). Add the others over SSH (config Host aliases)."
      echo

      listed="$("$herdr_bin" machine list --json 2>/dev/null || echo '[]')"
      echo "Currently saved:"
      echo "$listed" | ${pkgs.jq}/bin/jq -r '
        (if type == "array" then . else .machines // .result // [] end)
        | if length == 0 then "  (none)"
          else .[] | "  " + ((.label // .id // "?") | tostring) + " -> " + ((.target // .ssh_target // .host // "") | tostring)
          end
      ' 2>/dev/null || echo "  (could not parse machine list)"
      echo

      missing=()
      for host in "''${hosts[@]}"; do
        if [[ "$host" == "$this" ]]; then
          echo "  skip $host (this machine is Local)"
          continue
        fi
        echo "  herdr machine add $host --label ''${labels[$host]}"
        missing+=("$host")
      done
      echo
      echo "Phone/iPad: herdr-mobile-relay PWA, or ssh <host> then herdr. Not Happier."
      echo "Relay setup (once per machine):"
      echo "  herdr plugin action invoke setup --plugin herdr-mobile-relay.events"

      if [[ "''${1:-}" != "apply" ]]; then
        echo
        echo "Re-run with: herdr-lan apply"
        exit 0
      fi
      if [[ ! -t 0 ]]; then
        echo "herdr-lan apply needs an interactive terminal (SSH host keys / install prompts)" >&2
        exit 1
      fi
      for host in "''${missing[@]}"; do
        echo "Adding $host (''${labels[$host]})..."
        "$herdr_bin" machine add "$host" --label "''${labels[$host]}" || \
          echo "herdr-lan: add $host failed (already saved, or needs herdr --remote $host)" >&2
      done
    '';
  };

  systemdUserServices = lib.optionalAttrs (!isDarwin) {
    herdr-server = {
      Unit = {
        Description = "Herdr agent multiplexer (always-on server)";
        After = [ "default.target" ];
      };
      Service = {
        ExecStart = "${lib.getExe serve}";
        Restart = "on-failure";
        RestartSec = "5";
        TimeoutStartSec = "0";
        KillMode = "mixed";
        Environment = [
          "HOME=${homeDir}"
          "PATH=${agentPath}"
          "SHELL=${pkgs.zsh}/bin/zsh"
        ];
      };
      Install.WantedBy = [ "default.target" ];
    };
  };

  launchdAgents = {
    herdr-server = {
      command = lib.getExe serve;
      serviceConfig = {
        # Always-on: relaunch after crash. Stop with `launchctl stop` / disable
        # this agent, not `herdr server stop` (KeepAlive would bring it back).
        KeepAlive = true;
        RunAtLoad = true;
        WorkingDirectory = homeDir;
        StandardOutPath = "/tmp/herdr-server_${user}.out.log";
        StandardErrorPath = "/tmp/herdr-server_${user}.err.log";
        EnvironmentVariables = {
          HOME = homeDir;
          PATH = agentPath;
          SHELL = "${pkgs.zsh}/bin/zsh";
        };
      };
    };
  };
in
{
  inherit herdr worktrunk serve lan plugin idlePlugin;

  home.packages = [
    herdr
    worktrunk
    serve
    lan
    pkgs.go
    pkgs.fzf
    pkgs.jq
  ];

  home.file = {
    ".config/herdr/config.toml" = {
      text = configToml;
      force = true;
    };
    ".config/worktrunk/config.toml" = {
      text = worktrunkToml;
      force = true;
    };
  };

  home.activation = {
    herdrPlugins = lib.hm.dag.entryAfter [ "writeBoundary" "syncPiSettings" ] ''
      export PATH="${agentPath}:$PATH"
      herdr="${lib.getExe herdr}"
      mkdir -p "$HOME/.config/herdr" "$HOME/.pi/agent/extensions"

      "$herdr" plugin unlink nixos-config.pi-worktree >/dev/null 2>&1 || true
      "$herdr" plugin unlink nixos-config.agent-idle >/dev/null 2>&1 || true
      "$herdr" plugin link ${plugin} >/dev/null 2>&1 \
        || "$herdr" plugin link ${plugin} \
        || echo "herdr: WARNING failed to link pi-worktree plugin" >&2
      "$herdr" plugin link ${idlePlugin} >/dev/null 2>&1 \
        || "$herdr" plugin link ${idlePlugin} \
        || echo "herdr: WARNING failed to link agent-idle plugin" >&2

      ensure_plugin() {
        local spec="$1"
        if "$herdr" plugin list --json 2>/dev/null | ${pkgs.jq}/bin/jq -e --arg s "$spec" '
          [.. | strings] | any(contains($s))
        ' >/dev/null; then
          return 0
        fi
        echo "herdr: installing plugin $spec"
        "$herdr" plugin install "$spec" --yes || \
          echo "herdr: WARNING failed to install $spec (network?)" >&2
      }
      ensure_plugin disintegrator/trunkr
      ensure_plugin 0cv/herdr-mobile-relay

      if [[ -d "$HOME/.pi/agent" ]]; then
        "$herdr" integration install pi >/dev/null 2>&1 \
          || echo "herdr: WARNING integration install pi failed" >&2
      fi

      if "$herdr" status server >/dev/null 2>&1; then
        "$herdr" server reload-config >/dev/null 2>&1 || true
      fi
    '';
  };

  inherit systemdUserServices launchdAgents;
}
