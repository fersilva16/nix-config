{ mkUserModule, ... }:
mkUserModule {
  name = "arc";
  system.homebrew.casks = [ "arc" ];
}
