{ mkUserModule, ... }:
mkUserModule {
  name = "anytype";
  system.homebrew.casks = [ "anytype" ];
}
