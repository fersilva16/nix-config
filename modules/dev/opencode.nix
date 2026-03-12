{ username, pkgs, ... }:
let
  jsonFormat = pkgs.formats.json { };
  inherit (pkgs) tmux-extras;
in
{
  home-manager.users.${username} = {
    programs.opencode = {
      enable = true;
      settings = {
        theme = "flexoki";
        plugin = [
          "@simonwjackson/opencode-direnv"
          "@mohak34/opencode-notifier@latest"
          "oh-my-opencode@latest"
        ];
        permission = {
          external_directory = "allow";
        };
      };
    };

    xdg.configFile."opencode/oh-my-opencode.json".source = jsonFormat.generate "oh-my-opencode.json" {
      "$schema" =
        "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/oh-my-opencode.schema.json";
      agents = {
        sisyphus = {
          model = "anthropic/claude-opus-4-6";
          variant = "max";
        };
        oracle = {
          model = "anthropic/claude-opus-4-6";
          variant = "max";
        };
        explore = {
          model = "anthropic/claude-haiku-4-5";
        };
        multimodal-looker = {
          model = "opencode/glm-4.7-free";
        };
        prometheus = {
          model = "anthropic/claude-opus-4-6";
          variant = "max";
        };
        metis = {
          model = "anthropic/claude-opus-4-6";
          variant = "max";
        };
        momus = {
          model = "anthropic/claude-opus-4-6";
          variant = "max";
        };
        atlas = {
          model = "anthropic/claude-sonnet-4-5";
        };
        sisyphus-junior = {
          model = "anthropic/claude-sonnet-4-6";
        };
      };
      categories = {
        visual-engineering = {
          model = "anthropic/claude-opus-4-6";
          variant = "max";
        };
        ultrabrain = {
          model = "anthropic/claude-opus-4-6";
          variant = "max";
        };
        quick = {
          model = "anthropic/claude-haiku-4-5";
        };
        unspecified-low = {
          model = "anthropic/claude-sonnet-4-5";
        };
        unspecified-high = {
          model = "anthropic/claude-opus-4-6";
          variant = "max";
        };
        writing = {
          model = "anthropic/claude-sonnet-4-5";
        };
      };
    };

    xdg.configFile."opencode/opencode-notifier.json".source =
      jsonFormat.generate "opencode-notifier.json"
        {
          sound = true;
          notification = false;
          suppressWhenFocused = false;
          command = {
            enabled = true;
            path = "${tmux-extras}/bin/tmux-notify";
            args = [
              "add"
              "--event"
              "{event}"
              "{message}"
            ];
            minDuration = 0;
          };
        };
  };
}
