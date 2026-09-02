{ config, pkgs, lib, llm-agents-nix, ... }:
let
  user = "amitsheokand";
  agents = llm-agents-nix.packages.${pkgs.stdenv.hostPlatform.system};
  grokCli = pkgs.runCommand "grok-cli" { } ''
    mkdir -p $out/bin
    ln -s ${agents.grok}/bin/grok $out/bin/grok
  '';
  mlxMac = import ../../modules/shared/mlx-mac.nix { inherit user pkgs; };
  mlxCompact = import ../../modules/shared/mlx-compactor.nix { inherit user pkgs; };
  museSpark = import ../../modules/shared/muse-spark.nix { inherit pkgs lib; };
  zvecGrep = import ../../modules/shared/zvec-grep.nix { inherit pkgs lib; };
in
{
  imports = [
    ../../modules/darwin/home-manager.nix
    ../../modules/shared
  ];

  nix = {
    enable = false;
    package = pkgs.nix;
    settings = {
      trusted-users = [ "@admin" "${user}" ];
      substituters = [
        "https://nix-community.cachix.org"
        "https://cache.nixos.org"
        "https://cache.numtide.com"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      ];
    };
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  users.users.${user}.openssh.authorizedKeys.keys =
    import ../../modules/shared/ssh-keys.nix;

  # Inbound SSH on the LAN (System Settings → Sharing → Remote Login equivalent).
  services.openssh.enable = true;

  # Agent CLIs from llm-agents.nix: pi + OpenCode + Hermes + Grok (`grok` only).
  # Cursor via Homebrew/nixpkgs. Claude/Codex/prime-agent omitted.
  # Muse Code is a pinned Meta binary. OpenCode GUI = cask opencode-desktop.
  environment.systemPackages =
    (import ../../modules/darwin/packages.nix { inherit pkgs; })
    ++ [
      agents.pi
      agents.opencode
      agents.hermes-agent
      agents.hermes-desktop
      grokCli
      museSpark.museCode
      pkgs.nh
      (import ../../modules/shared/mlx-lane.nix { inherit pkgs; })
    ];

  # Grok /model picker: keep cloud grok-* and add local Gemma 4 MLX.
  environment.etc."grok/managed_config.toml".text =
    mlxMac.grokLocal + museSpark.grokToml;

  # Gemma 12B coder on :8080 — on demand (`mlx-lane gemma`). Not at login.
  launchd.user.agents.mlx-lm-server = {
    command = "${mlxMac.mlxLmServer}/bin/mlx-lm-server";
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = false;
      StandardOutPath = "/tmp/mlx-lm_${user}.out.log";
      StandardErrorPath = "/tmp/mlx-lm_${user}.err.log";
    };
  };

  # Compactor 4B on :8081 — default resident lane for Pi compact over LAN.
  launchd.user.agents.mlx-lm-compact = {
    command = "${mlxCompact.mlxLmCompactServer}/bin/mlx-lm-compact";
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/tmp/mlx-lm-compact_${user}.out.log";
      StandardErrorPath = "/tmp/mlx-lm-compact_${user}.err.log";
    };
  };

  # Muse Spark Chat Completions: uniquify reused tool_call_id `call_0`.
  launchd.user.agents.muse-spark-proxy = museSpark.launchdAgents.muse-spark-proxy;

  launchd.user.agents.zvec-grep = zvecGrep.launchdAgents.zvec-grep;

  system = {
    # Turn off NIX_PATH warnings now that we're using flakes
    checks.verifyNixPath = false;
    primaryUser = user;
    stateVersion = 4;
    defaults = {
      LaunchServices = {
        LSQuarantine = false;
      };
      NSGlobalDomain = {
        AppleShowAllExtensions = true;
        ApplePressAndHoldEnabled = false;

        # 120, 90, 60, 30, 12, 6, 2
        KeyRepeat = 2;

        # 120, 94, 68, 35, 25, 15
        InitialKeyRepeat = 15;
        "com.apple.mouse.tapBehavior" = 1;
        "com.apple.sound.beep.volume" = 0.0;
        "com.apple.sound.beep.feedback" = 0;
      };
      dock = {
        autohide = false;
        show-recents = false;
        launchanim = true;
        mouse-over-hilite-stack = true;
        orientation = "left";
        tilesize = 48;
      };
      finder = {
        _FXShowPosixPathInTitle = false;
      };
      trackpad = {
        Clicking = true;
        TrackpadThreeFingerDrag = true;
      };
    };
    keyboard = {
      enableKeyMapping = true;
    };
  };

  networking.hostName = "ai-mac";

  # nix-darwin has no `networking.hosts` (NixOS-only; the darwin port was
  # reverted because a symlink /etc/hosts breaks macOS name resolution).
  # Idempotently keep LAN names in the real file when mDNS is flaky
  # (Asahi has advertised as vaayu-2.local).
  system.activationScripts.lanHosts.text = ''
    echo "setting up LAN /etc/hosts entries..." >&2
    /usr/bin/python3 - <<'PY'
    from pathlib import Path

    path = Path("/etc/hosts")
    begin = "# nixos-config-lan-begin"
    end = "# nixos-config-lan-end"
    block = (
        f"{begin}\n"
        "192.168.1.15\tnixos nixos.local\n"
        "192.168.1.16\todie odie.local\n"
        "192.168.1.18\tvaayu vaayu.local\n"
        f"{end}\n"
    )
    text = path.read_text() if path.exists() else ""
    if begin in text:
        pre, rest = text.split(begin, 1)
        rest = rest.split(end, 1)[1].lstrip("\n") if end in rest else ""
        text = pre.rstrip("\n") + ("\n" if rest.strip() else "") + rest
    text = text.rstrip("\n")
    new = (text + "\n\n" + block) if text else block
    if new != (path.read_text() if path.exists() else ""):
        path.write_text(new)
    PY
  '';
}
