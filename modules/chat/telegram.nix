{ mkUserModule, ... }:
mkUserModule {
  name = "telegram";
  system.homebrew.casks = [ "telegram" ];
}
