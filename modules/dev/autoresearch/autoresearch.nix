{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  # autoresearch-opencode: autonomous experiment loop skill + slash command.
  # Upstream is shipped as plain markdown, no build step required.
  autoresearch-src = pkgs.fetchFromGitHub {
    owner = "moedesux";
    repo = "autoresearch-opencode";
    rev = "679a3310b3cb26dc84b81bddf4d450778d53cf35";
    hash = "sha256-P7ZZxmFiS6X5QrH14Dhi3TAKeZ6u7dKI7Az+FSFHhYA=";
  };

  # Upstream's command frontmatter has an unquoted description containing
  # ": ", which omo's strict YAML parser rejects. Quote it; --replace-fail
  # breaks the build if upstream changes the line.
  omo-command = pkgs.runCommand "autoresearch-omo-command.md" { } ''
    substitute ${autoresearch-src}/commands/autoresearch.md $out \
      --replace-fail \
        'description: Start or resume autoresearch experiment loop (optional args: off|dashboard)' \
        'description: "Start or resume autoresearch experiment loop (optional args: off|dashboard)"'
  '';
in
mkUserModule {
  name = "autoresearch";
  home =
    { userCfg, ... }:
    {
      # The skill and the command; upstream's context-injection plugin is
      # opencode-only.
      home.file = lib.mkIf userCfg.omo-home.enable {
        ".omo/agent/skills/autoresearch/SKILL.md".source =
          "${autoresearch-src}/skills/autoresearch/SKILL.md";
        ".omo/agent/prompts/autoresearch.md".source = omo-command;
      };
    };
}
