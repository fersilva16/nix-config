{ mkUserModule, ... }:
mkUserModule {
  name = "pritunl";
  system.homebrew.casks = [ "pritunl" ];
}
