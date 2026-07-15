{
  mkUserModule,
  pkgs,
  lib,
  inputs,
  system,
  forPlatform,
  ...
}:
let
  serverPort = 4096;

  # Real opencode binary with patches applied
  opencode-unwrapped = inputs.opencode.packages.${system}.default.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./patches/cursor-style-and-blink.patch
      ./patches/generate-remove-prettier.patch
      ./patches/relax-bun-version-check.patch
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
        forPlatform
        opencode-unwrapped
        serverPort
        ;
    };
    direnv-plugin = import ./direnv-plugin.nix { inherit pkgs; };
    framelink = import ./framelink.nix { inherit pkgs; };
    agentation = import ./agentation.nix { inherit pkgs; };
    autoresearch = import ./autoresearch.nix { inherit pkgs; };
    anthropic-auth = import ./anthropic-auth.nix { inherit pkgs; };
    ponytail = import ./ponytail.nix { inherit pkgs lib; };
    cache = import ./cache.nix { };
    omo-gitignore = import ./omo-gitignore.nix { };
    omo = import ./omo.nix { inherit pkgs; };
  };
  home =
    { username, ... }:
    {
      programs.opencode = {
        enable = true;
        package = lib.mkDefault opencode-unwrapped;
        tui = {
          theme = "flexoki";
          cursor_style = "line";
          cursor_blink = true;
        };
        settings = {
          plugin = [ "@rama_nigg/open-cursor@2.4.5" ];
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
            bash = {
              "*" = "allow";
              # opencode matches the FULL command string, anchored start-to-end,
              # last-matching-rule-wins. A leading "*" is required so prefixes
              # like `cd /path && gh ...` still match (without it, `^gh ...`
              # never matches a command that starts with `cd`).
              "*gh pr comment*" = "deny";
              "*gh issue comment*" = "deny";
              "*gh pr review*" = "deny";
              "*gh api*comments*" = "deny";
              "*gh api*replies*" = "deny";
              "*gh pr create*" = "ask";
            };
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
              model = "anthropic/claude-haiku-4-5";
            };
          };

        };
      };

      xdg.configFile = {
        # Global instructions opencode injects into every session's system prompt.
        "opencode/AGENTS.md".text = ''
          # Global instructions

          ## Never speak as me on GitHub
          Never post or reply to comments on GitHub on my behalf. This includes
          PR/issue comments, review comments and their replies, and reviews —
          whether via `gh`, the GitHub REST/GraphQL API, or any MCP/tool. PR and
          issue bodies are fine. Reading GitHub is fine. If a comment/reply
          genuinely seems needed, draft the text and let me post it myself.
        '';
      };
    };
}
