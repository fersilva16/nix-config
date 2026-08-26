{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
mkUserModule {
  name = "lazygit";
  requires = [ "git" ];
  home =
    { userCfg, ... }:
    {
      # prefix+l splits a pane running lazygit, replacing tmux's last-window.
      #
      # Run through a LOGIN fish, not the bare binary. A command passed to
      # split-window is exec'd from the tmux server's environment, which is
      # whatever the server was launched with — here /usr/bin:/bin and the
      # tmux store path, no ~/.nix-profile/bin. A bare `lazygit` is not found,
      # the pane dies before it draws, and the split looks like it opens and
      # instantly closes. An absolute store path would fix launching but not
      # the customCommands below, which shell out to fish, gh and opencode and
      # would inherit that same stripped PATH. The login shell fixes both.
      programs.tmux.extraConfig = lib.mkIf userCfg.tmux.enable ''
        bind-key l split-window -h -c "#{pane_current_path}" '${pkgs.fish}/bin/fish -lc lazygit'
      '';

      programs.lazygit = {
        enable = true;
        settings = {
          customCommands = [
            {
              key = "<c-a>";
              context = "files";
              # --title tags the session with its origin. These runs need the repo
              # cwd to see staged changes, so unlike `lin ai` they cannot be parked
              # in a scratch dir and will show up in this project's session picker.
              command = ''opencode run --title "lazygit commit" -m "anthropic/claude-haiku-4-5" "Look at the staged changes and create a commit following conventional commit conventions. Just commit directly."'';
              output = "terminal";
              description = "Generate commit with OpenCode";
            }
            {
              key = "H";
              context = "global";
              command = ''opencode run --title "lazygit: {{.Form.Prompt}}" -m "anthropic/claude-haiku-4-5" "{{.Form.Prompt}}"'';
              output = "terminal";
              description = "AI help (haiku)";
              prompts = [
                {
                  type = "input";
                  title = "AI Help";
                  key = "Prompt";
                }
              ];
            }
            {
              key = "O";
              context = "localBranches";
              command = "git push && gh pr create --web";
              description = "Create PR (push + open in browser)";
              output = "log";
              loadingText = "Creating PR...";
            }
            {
              key = "<c-o>";
              context = "localBranches";
              command = ''fish -c "ghpc"'';
              description = "Create PR (push + fill + open)";
              output = "log";
              loadingText = "Creating PR...";
            }
            {
              key = "<c-x>";
              context = "localBranches";
              command = ''fish -c "ghpm"'';
              description = "Merge PR (squash)";
              output = "log";
              loadingText = "Merging PR...";
            }
            {
              key = "<c-p>";
              context = "localBranches";
              command = ''fish -c "ghpcm"'';
              description = "Create + Merge PR";
              output = "terminal";
              loadingText = "Creating and merging PR...";
            }
          ];
          gui = {
            nerdFontsVersion = "3";
            theme = {
              activeBorderColor = [
                "#205EA6"
                "bold"
              ]; # blue
              inactiveBorderColor = [ "#CECDC3" ]; # ui-3
              optionsTextColor = [ "#205EA6" ]; # blue
              selectedLineBgColor = [ "#E6E4D9" ]; # ui
              selectedRangeBgColor = [ "#DAD8CE" ]; # ui-2
              cherryPickedCommitBgColor = [ "#24837B" ]; # cyan
              cherryPickedCommitFgColor = [ "#FFFCF0" ]; # paper
              unstagedChangesColor = [ "#AF3029" ]; # red
              defaultFgColor = [ "#100F0F" ]; # tx
            };
          };
        };
      };
    };
}
