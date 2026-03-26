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
      # Custom flexoki theme with hardcoded light-mode colors.
      # Overrides the built-in flexoki which uses dark/light variants —
      # if the TUI misdetects the terminal mode, code blocks become
      # invisible (dark-mode cream text on a light background).
      # Using direct hex values bypasses mode detection entirely.
      "opencode/themes/flexoki.json".source = jsonFormat.generate "flexoki.json" {
        "$schema" = "https://opencode.ai/theme.json";
        theme = {
          primary = "#205EA6";
          secondary = "#5E409D";
          accent = "#BC5215";
          error = "#AF3029";
          warning = "#BC5215";
          success = "#66800B";
          info = "#24837B";
          text = "#100F0F";
          textMuted = "#6F6E69";
          background = "#FFFCF0";
          backgroundPanel = "#F2F0E5";
          backgroundElement = "#E6E4D9";
          border = "#B7B5AC";
          borderActive = "#878580";
          borderSubtle = "#CECDC3";
          diffAdded = "#66800B";
          diffRemoved = "#AF3029";
          diffContext = "#6F6E69";
          diffHunkHeader = "#205EA6";
          diffHighlightAdded = "#66800B";
          diffHighlightRemoved = "#AF3029";
          diffAddedBg = "#D5E5D5";
          diffRemovedBg = "#F7D8DB";
          diffContextBg = "#F2F0E5";
          diffLineNumber = "#6F6E69";
          diffAddedLineNumberBg = "#C5D5C5";
          diffRemovedLineNumberBg = "#E7C8CB";
          markdownText = "#100F0F";
          markdownHeading = "#5E409D";
          markdownLink = "#205EA6";
          markdownLinkText = "#24837B";
          markdownCode = "#24837B";
          markdownBlockQuote = "#AD8301";
          markdownEmph = "#AD8301";
          markdownStrong = "#BC5215";
          markdownHorizontalRule = "#6F6E69";
          markdownListItem = "#BC5215";
          markdownListEnumeration = "#24837B";
          markdownImage = "#A02F6F";
          markdownImageText = "#24837B";
          markdownCodeBlock = "#100F0F";
          syntaxComment = "#6F6E69";
          syntaxKeyword = "#66800B";
          syntaxFunction = "#BC5215";
          syntaxVariable = "#205EA6";
          syntaxString = "#24837B";
          syntaxNumber = "#5E409D";
          syntaxType = "#AD8301";
          syntaxOperator = "#6F6E69";
          syntaxPunctuation = "#6F6E69";
        };
      };

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
