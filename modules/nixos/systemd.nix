{ config, pkgs, lib, ... }:

let
  user = "amitsheokand";
in
{
  # ========================================
  # Development Environment Services (Examples)
  # ========================================
  # NOTE: These are example services from the original config.
  # Customize or remove them based on your needs.
  # They demonstrate how to:
  # 1. Auto-start development environments in tmux on login
  # 2. Run scheduled tasks with systemd timers
  
  systemd = {
    # === Example Development Environment Services ===
    # Uncomment and customize for your own projects
    
    # user.services.my-project-devenv = {
    #   description = "Start my-project development environment in tmux";
    #   wantedBy = [ "default.target" ];
    #   after = [ "graphical-session.target" ];
    #   serviceConfig = {
    #     Type = "forking";
    #     ExecStart = "${pkgs.writeShellScript "start-my-project" ''
    #       cd /home/${user}/.local/share/src/my-project
    #       export TMUX_TMPDIR=/run/user/1000
    #       ${pkgs.tmux}/bin/tmux -S /run/user/1000/tmux-my-project new-session -d -s my-project "${pkgs.nix}/bin/nix develop --impure -c bash -c \"devenv up; exec bash\""
    #     ''}";
    #     ExecStop = "${pkgs.tmux}/bin/tmux -S /run/user/1000/tmux-my-project kill-session -t my-project";
    #     RemainAfterExit = "no";
    #     Environment = [
    #       "PATH=/run/current-system/sw/bin:/home/${user}/.nix-profile/bin:/etc/profiles/per-user/${user}/bin:/nix/var/nix/profiles/default/bin:/run/wrappers/bin:/usr/bin:/bin"
    #     ];
    #   };
    # };

    # === Example Scheduled Services ===
    services = {
      # Example: Automated task service
      # my-scheduled-task = {
      #   description = "My Scheduled Task";
      #   after = [ "network.target" ];
      #   serviceConfig = {
      #     Type = "oneshot";
      #     User = "${user}";
      #     Group = "users";
      #     WorkingDirectory = "/home/${user}/my-project";
      #     ExecStart = "/path/to/script.sh";
      #     Environment = [
      #       "HOME=/home/${user}"
      #       "USER=${user}"
      #     ];
      #     StandardOutput = "journal";
      #     StandardError = "journal";
      #   };
      # };
    };

    timers = {
      # === Example Timers ===
      # Uncomment and customize for your scheduled tasks
      
      # my-scheduled-task = {
      #   description = "Run my task daily";
      #   wantedBy = [ "timers.target" ];
      #   timerConfig = {
      #     OnCalendar = "daily";
      #     RandomizedDelaySec = "3600";  # Random delay 0-60 minutes
      #     Persistent = true;            # Run if missed
      #   };
      # };
    };
  };
}
