# greetd + tuigreet login manager — lists both Wayland and X sessions
# (niri is the only session today; the xsessions dir is kept for whenever
# an X session returns).
{ mkSystemModule, pkgs, ... }:
mkSystemModule {
  name = "greetd";
  config =
    { config, ... }:
    let
      sessions = config.services.displayManager.sessionData.desktops;
      sessionDirs = "${sessions}/share/wayland-sessions:${sessions}/share/xsessions";
    in
    {
      services.greetd = {
        enable = true;
        settings.default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-session --sessions ${sessionDirs}";
      };
    };
}
