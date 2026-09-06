{ pkgs }:
let
  jsonFormat = pkgs.formats.json { };
  package = "oh-my-openagent";
  version = "4.19.4";
  plugin = "${package}@${version}";

  # opencode npm-installs its own plugins at runtime, so there is no
  # derivation to hang `applyPatches` off — the tree lands here instead.
  pkgRoot = "$HOME/.cache/opencode/packages/${plugin}/node_modules/${package}";
in
{
  default = true;

  home = {
    programs.opencode = {
      settings.plugin = [ plugin ];
      tui.plugin = [ plugin ];
    };

    # Backport of upstream 0fe0ac98 ("route categories through GPT-6 Astra
    # high"), which shipped in 5.0.0-beta.43 but never in the 4.x line.
    # Without it omo's `no-sisyphus-gpt` hook treats every gpt-* model that
    # isn't gpt-5.x as unsupported and force-switches Sisyphus → Hephaestus,
    # so each gpt-6-astra turn gets hijacked. The patch also routes gpt-6 to
    # the gpt-5-5 prompt family and defaults its variant to high, matching
    # upstream. Drop the whole block once the pin above reaches 5.x.
    home.activation.omoGpt6Sisyphus = {
      after = [ "writeBoundary" ];
      before = [ ];
      data = ''
        omo_index="${pkgRoot}/dist/index.js"
        if [ ! -f "$omo_index" ]; then
          echo "omo: ${plugin} not installed yet — GPT-6 patch applies on the next rebuild"
        elif ! grep -q 'function isGpt6Model' "$omo_index"; then
          ${pkgs.gnupatch}/bin/patch -p1 -d "${pkgRoot}" < ${./patches/omo-gpt6-sisyphus.patch}
        fi
      '';
    };

    # Plugin-registered agent overrides live here rather than in
    # programs.opencode.settings.agent.
    xdg.configFile."opencode/oh-my-openagent.json".source = jsonFormat.generate "oh-my-openagent.json" {
      "$schema" =
        "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/dist/oh-my-opencode.schema.json";
      agents = {
        sisyphus = {
          model = "anthropic/claude-opus-5";
          variant = "max";
        };
        prometheus = {
          model = "anthropic/claude-opus-5";
          variant = "max";
        };
        metis = {
          model = "anthropic/claude-opus-5";
          variant = "max";
        };
        hephaestus = {
          model = "openai/gpt-5.6-sol";
          variant = "high";
        };
        oracle = {
          model = "openai/gpt-5.5";
          variant = "high";
        };
        momus = {
          model = "openai/gpt-5.6-sol";
          variant = "xhigh";
        };
      };
      categories = {
        deep = {
          model = "openai/gpt-5.6-terra";
          variant = "xhigh";
        };
        ultrabrain = {
          model = "openai/gpt-5.6-sol";
          variant = "xhigh";
        };
        "unspecified-low" = {
          model = "openai/gpt-5.6-luna";
          variant = "xhigh";
        };
      };
    };
  };
}
