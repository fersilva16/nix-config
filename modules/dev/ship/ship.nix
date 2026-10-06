{ mkUserModule, lib, ... }:
# ship: `/ship` commits all local changes as one commit, pushes and opens a PR;
# `/ship merge` also squash-merges it. An omo extension, not a prompt template:
# it gathers the repo state before the turn starts, so the agent spends no tool
# calls on discovery (where past ship turns spent most of theirs).
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
