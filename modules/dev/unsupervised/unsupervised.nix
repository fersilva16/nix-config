{ mkUserModule, lib, ... }:
# unsupervised: `/unsupervised <task>` runs a task to the end with nobody
# watching: ultrawork, no questions, tested end to end, left uncommitted.
#
# omo arms ultrawork only when a typed prompt contains `ulw`/`ultrawork`: its
# hook reads the raw input (before prompt templates expand) and ignores
# extension-sent messages. So the template loads the `ultrawork` skill itself,
# which is the same directive.
mkUserModule {
  name = "unsupervised";
  home =
    { userCfg, ... }:
    {
      home.file = lib.mkIf userCfg.omo.enable {
        ".omo/agent/prompts/unsupervised.md".source = ./unsupervised.md;
      };
    };
}
