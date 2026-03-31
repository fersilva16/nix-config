{ mkUserModule, ... }:
mkUserModule {
  name = "figma";
  system.homebrew.casks = [ "figma" ];
}
