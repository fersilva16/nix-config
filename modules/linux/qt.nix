# Dark Qt to match the GTK side (./gtk.nix): Adwaita style in its dark
# variant, plus libadwaita-style window decorations.
{ mkUserModule, ... }:
mkUserModule {
  name = "qt";
  home.qt = {
    enable = true;
    platformTheme.name = "adwaita";
    style.name = "adwaita-dark";
  };
}
