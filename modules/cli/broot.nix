{ mkUserModule, ... }:
mkUserModule {
  name = "broot";
  home.programs.broot.enable = true;
}
