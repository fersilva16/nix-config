{ mkUserModule, ... }:
mkUserModule {
  name = "claude";
  system.homebrew.casks = [ "claude" ];
}
