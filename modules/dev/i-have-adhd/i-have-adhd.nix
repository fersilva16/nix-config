{ mkUserModule, lib, ... }:
# i-have-adhd: output-style ruleset — answer first, numbered steps, no
# preamble/recap/closers, plus a pre-send deletion checklist.
#
# `i-have-adhd.md` is a fork of https://github.com/ayghri/i-have-adhd (MIT) at
# rev d05af1e.  Dropped: `Persistence` (session toggling via a `/i-have-adhd`
# command that does not exist once the text is unconditionally in the
# prompt).  Changed: fact 4 and rule 6 ban time estimates instead of asking
# for them (AI estimates are calibrated to human speed and the reader plans
# by steps, not minutes); rule 9 is taken from upstream 4c76175.  Added:
# fact 6 ("in an agent harness, you act") and the rule 1/3/5 lines built on
# it, with rules 1-3 and 5 re-exampled around what only the reader does
# (decide, try, approve): the chat-era examples ("Run the script?", "Edit
# src/auth.ts", "run npm test and paste…") taught agents to stop and hand
# over steps they could take themselves.  Edit the
# markdown directly — it is a fork, not a mirror, so there is nothing to
# re-sync.
#
# Upstream ships it as a skill, but its frontmatter sets
# `disable-model-invocation: true`: the model can never invoke it, so as a
# skill in opencode it would be inert.  Upstream's own always-on recipe is to
# put the rules in AGENTS.md, which is what this does.
mkUserModule {
  name = "i-have-adhd";
  home =
    { userCfg, ... }:
    {
      # `xdg.configFile.<name>.text` is `types.lines`, so this concatenates onto
      # opencode's global AGENTS.md.
      xdg.configFile."opencode/AGENTS.md" = lib.mkIf userCfg.opencode.enable {
        text = "\n" + builtins.readFile ./i-have-adhd.md;
      };
      # omo only applies a ~/.omo/rules file whose frontmatter says so.
      home.file.".omo/rules/i-have-adhd.md" = lib.mkIf userCfg.omo.enable {
        text = "---\nalwaysApply: true\n---\n\n" + builtins.readFile ./i-have-adhd.md;
      };
    };
}
