{
  config,
  mkUserModule,
  forPlatform,
  pkgs,
  lib,
  ...
}:
mkUserModule {
  name = "steam";
  casks = [ "steam" ];
  # NixOS module wires the FHS runtime, 32-bit libs and udev rules for
  # controllers; a bare pkgs.steam in home.packages misses those.
  system = forPlatform {
    linux = {
      programs.steam = {
        enable = true;
        # Proton-GE shows up in Properties > Compatibility next to Valve's Proton.
        extraCompatPackages = [ pkgs.proton-ge-bin ];
      };
      # Steam's CHTTPClientThread (and some Proton games) take split-lock
      # traps every few seconds; the default mitigation sleeps the offending
      # thread on each one. SteamOS/Bazzite ship this off too.
      boot.kernel.sysctl."kernel.split_lock_mitigate" = 0;
      # Feral GameMode daemon: raises the CPU governor and priority while a
      # game runs. Per game in Steam: launch options `gamemoderun %command%`;
      # Heroic has a per-game GameMode toggle that uses the same daemon.
      programs.gamemode = {
        enable = true;
        settings = {
          # nice -10 for the game's threads. Nice only weighs tasks in the
          # same cgroup (the game vs Steam's shader compiles), so the work
          # in other slices yields through game-priority below.
          general.renice = 10;
          custom = {
            start = "${config.systemd.package}/bin/systemctl start game-priority.service";
            end = "${config.systemd.package}/bin/systemctl stop game-priority.service";
          };
        };
      };

      # Active while any game holds GameMode. Background work yields the
      # machine to it here; modules that run such work add their own lines
      # to `script` (yield) and `preStop` (take it back).
      systemd.services.game-priority = {
        description = "A game is running: background work yields CPU and GPU";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        # Under load each slice gets CPU by weight, nice does not cross
        # them: user.slice (the game) outweighs system.slice (nix builds,
        # services) 10:1. An empty value restores the default.
        script = "systemctl set-property --runtime user.slice CPUWeight=1000";
        preStop = "systemctl set-property --runtime user.slice CPUWeight=";
      };

      # gamemoded runs as the player, so the gamemode group may start and
      # stop that one unit with no password.
      security.polkit.extraConfig = ''
        polkit.addRule(function (action, subject) {
          if (action.id == "org.freedesktop.systemd1.manage-units" &&
              action.lookup("unit") == "game-priority.service" &&
              ["start", "stop"].indexOf(action.lookup("verb")) >= 0 &&
              subject.isInGroup("gamemode")) {
            return polkit.Result.YES;
          }
        });
      '';
    };
  };
  # gamemode's polkit rule only lets the `gamemode` group switch the CPU
  # governor without a password prompt.
  user = forPlatform { linux.extraGroups = [ "gamemode" ]; };
  # Steam draws its own toasts as floating X11 windows instead of using the
  # notification daemon, so niri opens them centered. Pin them bottom-right
  # (niri wiki, Application Issues). `or false`: the niri option only
  # exists on linux hosts.
  home =
    { userCfg, ... }:
    {
      xdg.configFile = lib.mkIf (userCfg.niri.enable or false) {
        "niri/config.kdl".text = ''

          window-rule {
              match app-id="steam" title=r#"^notificationtoasts_\d+_desktop$"#
              default-floating-position x=10 y=10 relative-to="bottom-right"
          }
        '';
      };
    };
}
