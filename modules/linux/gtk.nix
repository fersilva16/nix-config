{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "gtk";
  home = {
    gtk = {
      enable = true;
      theme = {
        name = "Materia-dark";
        package = pkgs.materia-theme;
      };
    };
  };
}
