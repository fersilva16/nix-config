{ mkUserModule, ... }:
mkUserModule {
  name = "teams";
  casks = [ "microsoft-teams" ];
}
