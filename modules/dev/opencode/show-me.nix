_:
# show-me: `/show-me` explains the current topic visually — pseudocode, call
# trees, component trees, shallow file trees, Mermaid, and diffs *of* those
# shapes rather than of code.
#
# `show-me.md` is a fork of https://github.com/humanlayer/skills (MIT),
# `plugins/show-me` at v1.0.1.  Edit the markdown directly — it is a fork, not
# a mirror, so there is nothing to re-sync.
#
# Two changes from upstream.  Dropped the HTML-artifact bullet ("write one
# focused HTML file [...] then `open` it"): it litters the repo with
# `show-me-*.html` and reaches for a slide deck where a Mermaid diagram
# answers the question.  Shipped as a slash command rather than upstream's
# skill, because its description ("help the user understand the current topic
# visually") carries no trigger phrases — as a skill opencode's matcher would
# fire it arbitrarily or never.  Explicit `/show-me` is the intent anyway.
{
  # Discovered under `{command,commands}/**/*.md` in the config dir.
  home.xdg.configFile."opencode/commands/show-me.md".source = ./show-me.md;
}
