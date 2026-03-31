{ mkUserModule, ... }:
mkUserModule {
  name = "ngrok";
  system.homebrew.casks = [ "ngrok" ];
}
