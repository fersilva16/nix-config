{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  # ponytail: makes the agent think like the laziest senior dev — YAGNI,
  # stdlib/native over dependencies, shortest working diff.  Shipped as plain
  # markdown + dependency-free CommonJS hooks, no build step (like
  # autoresearch).
  #
  ponytail-src = pkgs.fetchFromGitHub {
    owner = "DietrichGebert";
    repo = "ponytail";
    rev = "2ed6c52c9d7e5e56942508591085fd45dea277d3";
    hash = "sha256-bGdXvzhWPwGdz3T2Yh2h6lf+3PBRFAfdBxP5pESmCHI=";
  };

  # Upstream ships slash commands (`.opencode/command/*.md`) and
  # trigger-activated skills (`skills/*/SKILL.md`).
  names = [
    "ponytail"
    "ponytail-audit"
    "ponytail-debt"
    "ponytail-help"
    "ponytail-review"
  ];

  # omo loads them as prompt templates and skills. Only upstream's opencode
  # plugin persists `/ponytail <level>`, so here it lasts for the session.
  omoFiles = lib.listToAttrs (
    lib.concatMap (n: [
      {
        name = ".omo/agent/prompts/${n}.md";
        value.source = "${ponytail-src}/.opencode/command/${n}.md";
      }
      {
        name = ".omo/agent/skills/${n}/SKILL.md";
        value.source = "${ponytail-src}/skills/${n}/SKILL.md";
      }
    ]) names
  );
in
mkUserModule {
  name = "ponytail";
  home =
    { userCfg, ... }:
    {
      home.file = lib.mkIf userCfg.omo-home.enable omoFiles;
    };
}
