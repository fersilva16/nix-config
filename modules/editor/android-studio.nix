{ mkUserModule, ... }:
mkUserModule {
  name = "android-studio";
  system.homebrew.casks = [ "android-studio" ];
}
