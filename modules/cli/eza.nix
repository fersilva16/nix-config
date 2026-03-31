{ mkUserModule, ... }:
mkUserModule {
  name = "eza";
  home.programs.eza.enable = true;
}
