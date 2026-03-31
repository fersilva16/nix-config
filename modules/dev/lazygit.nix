{ mkUserModule, ... }:
mkUserModule {
  name = "lazygit";
  home = {
    programs.lazygit = {
      enable = true;
      settings = {
        customCommands = [
          {
            key = "<c-a>";
            context = "files";
            command = ''opencode run -m "opencode/minimax-m2.5-free" "Look at the staged changes and create a commit following conventional commit conventions. Just commit directly."'';
            output = "terminal";
            description = "Generate commit with OpenCode";
          }
          {
            key = "H";
            context = "global";
            command = ''opencode run -m "opencode/minimax-m2.5-free" "{{.Form.Prompt}}"'';
            output = "terminal";
            description = "AI help (minimax)";
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
