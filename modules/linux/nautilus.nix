# File manager. Nautilus over a lighter one (thunar) because niri's portal
# (xdg-desktop-portal-gnome) draws its file chooser with Nautilus, so every
# "Open file" dialog is this app anyway. libadwaita, so it follows the
# dark color-scheme and the Ink colors (gtk.nix, noctalia.nix).
#
# udisks2 mounts USB drives from the sidebar; gvfs adds trash, MTP (phones)
# and smb:// browsing.
{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "nautilus";
  system = {
    # System-wide so the portal can reach it over D-Bus.
    environment.systemPackages = [ pkgs.nautilus ];
    services = {
      udisks2.enable = true;
      gvfs.enable = true;
    };
  };
  home = {
    xdg.mimeApps = {
      enable = true;
      defaultApplications."inode/directory" = "org.gnome.Nautilus.desktop";
    };
    # Apps rewrite mimeapps.list ("set as default"); home-manager owns it.
    xdg.configFile."mimeapps.list".force = true;
  };
}
