{ mkUserModule, ... }:
mkUserModule {
  name = "yubikey";
  casks = [ "yubico-authenticator" ];
}
