{ mkUserModule, ... }:
mkUserModule {
  name = "obs";
  home.programs.obs-studio.enable = true;
}
