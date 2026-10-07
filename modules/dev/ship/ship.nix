{ mkUserModule, lib, ... }:
# ship: `/ship` commits, pushes and opens a PR; `/ship merge` also merges it.
mkUserModule {
  name = "ship";
  home =
    { userCfg, ... }:
    {
      home.file = lib.mkIf userCfg.omo.enable {
        ".omo/agent/extensions/ship".source = ./extension;
      };
    };
}
