{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
mkUserModule {
  name = "feh";
  home = {
    home.packages = with pkgs; [ feh ];
    xdg.mimeApps = {
      enable = true;
      defaultApplications = lib.genAttrs [
        "image/png"
        "image/jpeg"
        "image/gif"
        "image/webp"
        "image/bmp"
        "image/tiff"
      ] (_: "feh.desktop");
    };
    # Apps rewrite mimeapps.list ("set as default"); home-manager owns it.
    xdg.configFile."mimeapps.list".force = true;
  };
}
