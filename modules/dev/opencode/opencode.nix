{
  mkUserModule,
  pkgs,
  lib,
  inputs,
  system,
  ...
}:
let
  jsonFormat = pkgs.formats.json { };
  serverPort = 4096;

  # Real opencode binary with patches applied
  opencode-unwrapped = inputs.opencode.packages.${system}.default.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./patches/cursor-style-and-blink.patch
      ./patches/generate-remove-prettier.patch
    ];
  });
in
mkUserModule {
  name = "opencode";
  parts = {
    server = import ./server.nix {
      inherit
        pkgs
        lib
        opencode-unwrapped
        serverPort
        ;
    };
    direnv-plugin = import ./direnv-plugin.nix { inherit pkgs; };
    framelink = import ./framelink.nix { inherit pkgs; };
    agentation = import ./agentation.nix { inherit pkgs; };
  };
  home =
    { username, ... }:
    {
      programs.opencode = {
        enable = true;
        package = lib.mkDefault opencode-unwrapped;
        settings = {
          theme = "flexoki";
          plugin = [
            "@ex-machina/opencode-anthropic-auth@1.7.5"
            "oh-my-openagent@3.17.4"
            "@rama_nigg/open-cursor@2.3.20"
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
              template = "!`fish -c lin`";
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
          agent = {
            title = {
              model = "opencode/minimax-m2.5-free";
            };
          };

        };
      };

      xdg.configFile = {
        "opencode/tui.json".source = jsonFormat.generate "tui.json" {
          cursor_style = "line";
          cursor_blink = true;
        };

        # oh-my-openagent plugin config. The plugin reads agent overrides from
        # this file (NOT from opencode's `settings.agent.*`), so model bumps for
        # plugin-registered agents (sisyphus, prometheus, oracle, metis, momus)
        # must live here. Only model + variant are overridden; prompts, tools,
        # and fallback chains are inherited from the plugin defaults.
        #
        # `variant = "max"` matches the plugin's own built-in fallback-chain
        # defaults for these agents (see AGENT_MODEL_REQUIREMENTS in the plugin
        # source). When we specify `model` alone, the plugin's resolver returns
        # `{ model, provenance: "override" }` with NO variant attached — the
        # variant only rides along with fallback-chain entries. So overriding
        # just `model` silently drops `max`. We re-attach it explicitly.
        "opencode/oh-my-openagent.json".source = jsonFormat.generate "oh-my-openagent.json" {
          "$schema" =
            "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/dist/oh-my-opencode.schema.json";
          agents = {
            sisyphus = {
              model = "anthropic/claude-opus-4-7";
              variant = "max";
            };
            prometheus = {
              model = "anthropic/claude-opus-4-7";
              variant = "max";
            };
            oracle = {
              model = "anthropic/claude-opus-4-7";
              variant = "max";
            };
            metis = {
              model = "anthropic/claude-opus-4-7";
              variant = "max";
            };
            momus = {
              model = "anthropic/claude-opus-4-7";
              variant = "max";
            };
          };
        };
      };
    };
}
