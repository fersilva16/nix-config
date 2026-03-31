{ mkUserModule, ... }:
mkUserModule {
  name = "sony";
  system.homebrew.casks = [ "sony-ps-remote-play" ];
}
