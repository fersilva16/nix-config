{ pkgs, lib }:
let
  # ponytail: makes the agent think like the laziest senior dev — YAGNI,
  # stdlib/native over dependencies, shortest working diff.  Shipped as plain
  # markdown + dependency-free CommonJS hooks, no build step (like
  # autoresearch).
  #
  # The opencode plugin (`.opencode/plugins/ponytail.mjs`) injects the ruleset
  # into every chat's system prompt at the active intensity and persists
  # `/ponytail <level>` switches.  It `require`s `../../hooks/*.js` and reads
  # `../skills/ponytail/SKILL.md` relative to its own file, so it must point at
  # the full source tree — the nix store preserves it, so a `file://` URL into
  # the store path resolves all siblings.  Loaded in-process by opencode's Bun
  # runtime; the README's `node`-on-PATH requirement is only for the Claude
  # Code / Codex lifecycle hooks, not this plugin.
  ponytail-src = pkgs.fetchFromGitHub {
    owner = "DietrichGebert";
    repo = "ponytail";
    rev = "adad50d9b393926b2dd5ed7225dcb1848b9df408";
    hash = "sha256-Q6vlkbTfBFrNFTxEwYeMe5ciOe6QdULegvExwT//gJs=";
  };

  # Slash commands (`.opencode/command/*.md`) and trigger-activated skills
  # (`skills/*/SKILL.md`).  Command files are self-contained prompts; the
  # `/ponytail` mode switch is persisted by the plugin's
  # `command.execute.before` hook.
  names = [
    "ponytail"
    "ponytail-audit"
    "ponytail-debt"
    "ponytail-help"
    "ponytail-review"
  ];

  commandFiles = lib.listToAttrs (
    map (n: {
      name = "opencode/commands/${n}.md";
      value.source = "${ponytail-src}/.opencode/command/${n}.md";
    }) names
  );

  skillFiles = lib.listToAttrs (
    map (n: {
      name = "opencode/skills/${n}/SKILL.md";
      value.source = "${ponytail-src}/skills/${n}/SKILL.md";
    }) names
  );
in
{
  home = {
    programs.opencode.settings.plugin = [
      "file://${ponytail-src}/.opencode/plugins/ponytail.mjs"
    ];

    xdg.configFile = commandFiles // skillFiles;
  };
}
