{ mkUserModule, lib, ... }:
# ship: `/ship [merge]` commits all local changes as one conventional commit,
# pushes, opens a PR (or updates the branch's open one) and, with `merge`,
# squash-merges it. Collapses the usual "commit it" / "open a PR and merge"
# chain into one command.
#
# An omo prompt template: templates only substitute arguments and can't run
# shell, so the prompt has the agent run the discovery itself in one batch.
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
