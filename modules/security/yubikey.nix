{ mkUserModule, ... }:
mkUserModule {
  name = "yubikey";
  system.homebrew.casks = [ "yubico-authenticator" ];
}
