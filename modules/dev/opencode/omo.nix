{ pkgs }:
let
  jsonFormat = pkgs.formats.json { };
  plugin = "oh-my-openagent@4.18.1";
in
{
  default = true;

  home = {
    programs.opencode = {
      settings.plugin = [ plugin ];
      tui.plugin = [ plugin ];
    };

    # Plugin-registered agent overrides live here rather than in
    # programs.opencode.settings.agent.
    xdg.configFile."opencode/oh-my-openagent.json".source = jsonFormat.generate "oh-my-openagent.json" {
      "$schema" =
        "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/dist/oh-my-opencode.schema.json";
      agents = {
        sisyphus = {
          model = "anthropic/claude-fable-5";
        };
        prometheus = {
          model = "anthropic/claude-fable-5";
        };
        metis = {
          model = "anthropic/claude-fable-5";
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
