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
    patches = (old.patches or [ ]) ++ [ ./patches/cursor-style-and-blink.patch ];
  });
in
mkUserModule {
  name = "opencode";
  parts = {
    server = import ./server.nix { inherit pkgs opencode-unwrapped serverPort; };
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
            "@ex-machina/opencode-anthropic-auth@0.2.1"
            "@mohak34/opencode-notifier@0.1.36"
            "oh-my-opencode@3.14.0"
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
      };
    };
}
