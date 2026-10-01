{
  mkUserModule,
  pkgs,
  lib,
  inputs,
  system,
  ...
}:
let
  # Real opencode binary with patches applied
  opencode = inputs.opencode.packages.${system}.default.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./patches/edit-tool-dollar-substitution.patch
      ./patches/generate-remove-prettier.patch
      ./patches/relax-bun-version-check.patch
      ./patches/retry-spliced-anthropic-stream.patch
    ];
  });
in
mkUserModule {
  name = "opencode";
  parts = {
    direnv-plugin = import ./direnv-plugin.nix { inherit pkgs; };
    framelink = import ./framelink.nix { inherit pkgs; };
    agentation = import ./agentation.nix { inherit pkgs; };
    anthropic-auth = import ./anthropic-auth.nix { inherit pkgs; };
    cache = import ./cache.nix { };
    omo-gitignore = import ./omo-gitignore.nix { };
    omo = import ./omo.nix { inherit pkgs lib; };
    codegraph = import ./codegraph.nix { inherit pkgs; };
    worktree-move = import ./worktree-move.nix { };
  };
  home =
    { username, ... }:
    {
      programs.opencode = {
        enable = true;
        package = opencode;
        tui = {
          theme = "flexoki";
          cursor = {
            style = "line";
            blinking = true;
          };
        };
        settings = {
          # Disable worktree snapshot/diff tracking: on large monorepos it
          # re-reads every file + the full git index in a loop, pinning CPU
          # (anomalyco/opencode#30086). Costs the file-revert/undo feature.
          snapshot = false;
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
        # `types.lines`, so other modules concatenate onto this — `i-have-adhd`
        # (output style) and `cli/fish.nix` (fish syntax) both append sections.
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
