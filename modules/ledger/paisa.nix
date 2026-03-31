{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "paisa";
  home = {
    home.packages = with pkgs; [ paisa ];

    home.file."Documents/paisa/paisa.yaml" = {
      source = ./paisa.yaml;
      force = true;
    };
  };
}
