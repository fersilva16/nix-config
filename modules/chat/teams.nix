{ mkUserModule, ... }:
mkUserModule {
  name = "teams";
  system.homebrew.casks = [ "microsoft-teams" ];
}
