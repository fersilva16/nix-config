{ mkUserModule, ... }:
mkUserModule {
  name = "selfcontrol";
  system.homebrew.casks = [ "selfcontrol" ];
}
