{ mkUserModule, ... }:
mkUserModule {
  name = "libreoffice";
  system.homebrew.casks = [ "libreoffice" ];
}
