{ mkUserModule, forPlatform, ... }:
mkUserModule {
  name = "openfortivpn";
  system = forPlatform {
    darwin.homebrew.brews = [ "openfortivpn" ];
  };
}
