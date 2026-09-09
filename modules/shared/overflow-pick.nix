# Daily overflow model pick: AA × OpenRouter / Zen / Hermes / Command-Code.
# Free catalogs are executors. Reviewers stay Cursor Grok + Muse in Pi.
# Does not pin a model. `overflow-assign` reuses today's file; the timer
# refreshes once a day.
{ pkgs, lib, user ? "amitsheokand" }:

let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  homeDir = if isDarwin then "/Users/${user}" else "/home/${user}";
  python = pkgs.python3;
  script = ./scripts/overflow-pick.py;
  overflowPick = pkgs.writeShellApplication {
    name = "overflow-pick";
    runtimeInputs = [ python ];
    text = ''
      exec ${python}/bin/python3 ${script} --refresh "$@"
    '';
  };
  overflowAssign = pkgs.writeShellApplication {
    name = "overflow-assign";
    runtimeInputs = [ python ];
    text = ''
      exec ${python}/bin/python3 ${script} "$@"
    '';
  };
in
{
  home.packages = [ overflowPick overflowAssign ];

  systemdUserServices = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    overflow-pick = {
      Unit = {
        Description = "Refresh Pi free/cheap overflow model (Artificial Analysis)";
        After = [ "network-online.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${lib.getExe overflowPick}";
        Environment = [
          "HOME=${homeDir}"
          "PATH=${lib.makeBinPath [ python pkgs.coreutils ]}:${homeDir}/.local/bin"
        ];
      };
    };
  };

  systemdUserTimers = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    overflow-pick = {
      Unit = { Description = "Daily Pi overflow model pick"; };
      Timer = {
        OnCalendar = "*-*-* 06:00:00";
        Persistent = true;
        RandomizedDelaySec = "300";
      };
      Install = { WantedBy = [ "timers.target" ]; };
    };
  };

  launchdAgents.overflow-pick = {
    command = lib.getExe overflowPick;
    serviceConfig = {
      RunAtLoad = true;
      StartCalendarInterval = { Hour = 6; Minute = 0; };
      StandardOutPath = "/tmp/overflow-pick_${user}.out.log";
      StandardErrorPath = "/tmp/overflow-pick_${user}.err.log";
      EnvironmentVariables = {
        HOME = homeDir;
        PATH = "${homeDir}/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
    };
  };
}
