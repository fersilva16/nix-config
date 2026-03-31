{ mkUserModule, ... }:
mkUserModule {
  name = "keyboardcleantool";
  system.homebrew.casks = [ "keyboardcleantool" ];
}
