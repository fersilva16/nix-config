{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  # autoresearch-opencode: autonomous experiment loop skill + slash command +
  # context-injection plugin.  Upstream is shipped as plain markdown and
  # TypeScript — no build step required.
  #
  # The plugin self-gates: it only injects autoresearch context when the
  # working directory contains an `autoresearch.md` file (and no
  # `.autoresearch-off` sentinel).  Safe to enable globally.
  autoresearch-src = pkgs.fetchFromGitHub {
    owner = "moedesux";
    repo = "autoresearch-opencode";
    rev = "679a3310b3cb26dc84b81bddf4d450778d53cf35";
    hash = "sha256-P7ZZxmFiS6X5QrH14Dhi3TAKeZ6u7dKI7Az+FSFHhYA=";
  };
in
mkUserModule {
  name = "autoresearch";
  home =
    { userCfg, ... }:
    {
      # Plugin loads via file:// URL — opencode resolves TypeScript directly via
      # Bun, no compilation needed (matches direnv-plugin pattern).
      programs.opencode.settings.plugin = lib.mkIf userCfg.opencode.enable [
        "file://${autoresearch-src}/plugins/autoresearch-context.ts"
      ];

      xdg.configFile = lib.mkIf userCfg.opencode.enable {
        # Skill: autonomous experiment-loop instructions.  Discovered by
        # opencode under `{skill,skills}/**/SKILL.md` in the config dir.
        "opencode/skills/autoresearch/SKILL.md".source = "${autoresearch-src}/skills/autoresearch/SKILL.md";

        # Slash command: `/autoresearch [goal]` — drives the experiment loop.
        # Discovered under `{command,commands}/**/*.md`.
        "opencode/commands/autoresearch.md".source = "${autoresearch-src}/commands/autoresearch.md";

        # Backup utility referenced by the skill (`./scripts/backup-state.sh`
        # lookup is project-relative, but having a known-good copy in the
        # config dir matches upstream's `install.sh` behavior and lets users
        # symlink it into their experiment projects).
        "opencode/scripts/backup-state.sh" = {
          source = "${autoresearch-src}/scripts/backup-state.sh";
          executable = true;
        };
      };

      # omo gets the skill and the command; the context-injection plugin is
      # opencode-only.
      home.file = lib.mkIf userCfg.omo.enable {
        ".omo/agent/skills/autoresearch/SKILL.md".source =
          "${autoresearch-src}/skills/autoresearch/SKILL.md";
        ".omo/agent/prompts/autoresearch.md".source = "${autoresearch-src}/commands/autoresearch.md";
      };
    };
}
