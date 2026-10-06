{ mkUserModule, lib, ... }:
# ship: `/ship` commits all local changes as one commit, pushes and opens a PR;
# `/ship merge` also squash-merges it.
mkUserModule {
  name = "ship";
  home =
    { userCfg, ... }:
    {
      home.file = lib.mkIf userCfg.omo.enable {
        ".omo/agent/prompts/ship.md".source = ./ship.md;
      };
    };
}
