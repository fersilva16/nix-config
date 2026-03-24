{
  username,
  pkgs,
  inputs,
  system,
  ...
}:
let
  jsonFormat = pkgs.formats.json { };
  inherit (pkgs)
    tmux-extras
    figma-developer-mcp
    agentation-mcp
    opencode-anthropic-auth
    ;
in
{
  home-manager.users.${username} = {
    programs.opencode = {
      enable = true;
      package = inputs.opencode.packages.${system}.default.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/cursor-style-and-blink.patch ];
        node_modules = old.node_modules.overrideAttrs {
          outputHash = "sha256-kZGUAE0fxFkFYrarWLQ6e40r5ZAF+GkRF2oZM8/erOM=";
        };
      });
      settings = {
        theme = "flexoki";
        plugin = [
          "file://${opencode-anthropic-auth}"
          "@simonwjackson/opencode-direnv@latest"
          "@mohak34/opencode-notifier@latest"
          "@kdcokenny/opencode-worktree@latest"
          "oh-my-opencode@latest"
          "@rama_nigg/open-cursor@latest"
        ];
        provider = {
          cursor-acp = {
            name = "Cursor ACP";
            npm = "@ai-sdk/openai-compatible";
            options = {
              baseURL = "http://127.0.0.1:32124/v1";
            };
            models = {
              "cursor-acp/auto" = {
                name = "Auto";
              };
              "cursor-acp/composer-1.5" = {
                name = "Composer 1.5";
              };
              "cursor-acp/composer-1" = {
                name = "Composer 1";
              };
            };
          };
        };
        command = {
          lin = {
            template = "Here is the Linear issue for this branch:\n\n!`lin`\n\nSummarize the issue and ask what I want to work on.";
            description = "Load Linear issue context";
          };
        };
        permission = {
          external_directory = "allow";
          read = {
            "*" = "allow";
            "*.env" = "deny";
            "*.env.*" = "allow";
          };
          edit = {
            "*" = "allow";
            "*.env" = "deny";
            "*.env.*" = "allow";
          };
        };
        mcp = {
          framelink = {
            enabled = false;
            type = "local";
            command = [
              "${figma-developer-mcp}/bin/figma-developer-mcp"
              "--stdio"
              "--env"
              "/Users/${username}/.config/figma/.env"
            ];
          };
          agentation = {
            enabled = false;
            type = "local";
            command = [
              "${agentation-mcp}/bin/agentation-mcp"
              "server"
            ];
          };
        };
      };
    };

    xdg.configFile = {
      "opencode/tui.json".source = jsonFormat.generate "tui.json" {
        cursor_style = "line";
        cursor_blink = true;
      };

      "opencode/oh-my-opencode.json".source = jsonFormat.generate "oh-my-opencode.json" {
        "$schema" =
          "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/oh-my-opencode.schema.json";
        agents = {
          build = {
            model = "anthropic/claude-opus-4-6";
          };
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

      "opencode/opencode-notifier.json".source = jsonFormat.generate "opencode-notifier.json" {
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
  };
}
