{
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
    };
  };
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
