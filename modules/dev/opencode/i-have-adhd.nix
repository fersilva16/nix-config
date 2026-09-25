_:
# i-have-adhd: output-style ruleset — answer first, numbered steps, no
# preamble/recap/closers, plus a pre-send deletion checklist.
#
# `i-have-adhd.md` is a fork of https://github.com/ayghri/i-have-adhd (MIT) at
# rev d05af1e.  Dropped: `Persistence` (session toggling via a `/i-have-adhd`
# command that does not exist once the text is unconditionally in the
# prompt).  Changed: fact 4 and rule 6 ban time estimates instead of asking
# for them (AI estimates are calibrated to human speed and the reader plans
# by steps, not minutes); rule 9 is taken from upstream 4c76175.  Edit the
# markdown directly — it is a fork, not a mirror, so there is nothing to
# re-sync.
#
# Upstream ships it as a skill, but its frontmatter sets
# `disable-model-invocation: true`: the model can never invoke it, so as a
# skill in opencode it would be inert.  Upstream's own always-on recipe is to
# put the rules in AGENTS.md, which is what this does.
{
  # `xdg.configFile.<name>.text` is `types.lines`, so this concatenates onto
  # the global AGENTS.md defined by the parent module.
  home.xdg.configFile."opencode/AGENTS.md".text = "\n" + builtins.readFile ./i-have-adhd.md;
}
