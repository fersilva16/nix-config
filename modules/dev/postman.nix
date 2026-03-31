{ mkUserModule, ... }:
mkUserModule {
  name = "postman";
  system.homebrew.casks = [ "postman" ];
}
