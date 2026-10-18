# Dark GTK, the same choice noctalia makes: its "Sync system theme"
# (colorSchemes.syncGsettings) sets adw-gtk3-dark + prefer-dark, but only when
# dark mode is toggled, which never happens with frozen settings. Declared
# here so it holds from the first login. adw-gtk3 is libadwaita's look ported
# to GTK 3, so GTK 3 and GTK 4 apps match; GTK 4 apps follow color-scheme.
{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "gtk";
  # home-manager writes these through dconf.
  system.programs.dconf.enable = true;
  home = {
    gtk = {
      enable = true;
      theme = {
        name = "adw-gtk3-dark";
        package = pkgs.adw-gtk3;
      };
    };
    dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
  };
}
