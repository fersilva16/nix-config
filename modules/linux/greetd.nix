# greetd + tuigreet login manager — lists both Wayland and X sessions
# (hyprland primary, i3 fallback; pick at login).
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
