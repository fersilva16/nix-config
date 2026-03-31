{ mkUserModule, ... }:
mkUserModule {
  name = "whatsapp";
  system.homebrew.casks = [ "whatsapp" ];
}
