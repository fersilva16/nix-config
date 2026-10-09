# Heroic — Epic/GOG/Amazon launcher (Rocket League lives on Epic).
#
# Games themselves are installed from inside Heroic (Wine/Proton-GE are
# downloaded there too); 32-bit graphics for Wine come from modules/linux/nvidia.nix.
{
  mkUserModule,
  forPlatform,
  pkgs,
  lib,
  ...
}:
mkUserModule {
  name = "heroic";
  casks = [ "heroic" ];
  home =
    { userCfg, ... }:
    {
      home.packages = forPlatform { linux = [ pkgs.heroic ]; };

      # Proton games (app-id steam_app_<id>) open fullscreen, so niri can
      # scan them out directly instead of compositing a tile, and get VRR.
      xdg.configFile = lib.mkIf userCfg.niri.enable {
        "niri/config.kdl".text = ''

          window-rule {
              match app-id="^steam_app_"
              open-fullscreen true
              variable-refresh-rate true
          }
        '';
      };
    };
}
