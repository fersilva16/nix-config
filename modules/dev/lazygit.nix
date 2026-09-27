{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  # prefix+l toggles a lazygit split, one per tmux session, replacing tmux's
  # last-window. The first press splits a pane running lazygit and tags it
  # @lazygit. Pressing it again breaks that pane out into a background window
  # of the same session; the next press joins it back beside the current
  # pane. lazygit keeps running throughout, so it comes back with the same
  # view, selection and scroll position. Quitting lazygit (q) closes the pane;
  # the next press starts a fresh one. The pane never leaves its session, so
  # killing the session (wtrm, kill-session) takes lazygit with it.
  #
  # lazygit runs through a LOGIN fish, not the bare binary. A command passed
  # to split-window is exec'd from the tmux server's environment, which is
  # whatever the server was launched with: here /usr/bin:/bin and the tmux
  # store path, no ~/.nix-profile/bin. A bare `lazygit` is not found, the
  # pane dies before it draws, and the split looks like it opens and
  # instantly closes. An absolute store path would fix launching but not the
  # customCommands below, which shell out to fish and gh and would inherit
  # that same stripped PATH. The login shell fixes both.
  tmux-lazygit = pkgs.writeShellApplication {
    name = "tmux-lazygit";
    runtimeInputs = [ pkgs.tmux ];
    text = ''
      pane=$(tmux list-panes -s -f '#{==:#{@lazygit},1}' -F '#{pane_id}' | head -1)
      if [ -z "$pane" ]; then
        pane=$(tmux split-window -h -P -F '#{pane_id}' \
          -c "$(tmux display-message -p '#{pane_current_path}')" \
          '${pkgs.fish}/bin/fish -lc lazygit')
        tmux set-option -p -t "$pane" @lazygit 1
      elif [ "$(tmux display-message -p -t "$pane" '#{window_id}')" != "$(tmux display-message -p '#{window_id}')" ]; then
        tmux join-pane -h -s "$pane"
      elif [ "$(tmux display-message -p '#{window_panes}')" -gt 1 ]; then
        tmux break-pane -d -s "$pane" -n lazygit
      else
        # Standing in lazygit's own background window: nothing to split from.
        tmux last-window
      fi
    '';
  };
in
mkUserModule {
  name = "lazygit";
  requires = [ "git" ];
  home =
    { userCfg, ... }:
    {
      home.packages = lib.optionals userCfg.tmux.enable [ tmux-lazygit ];
      programs.tmux.extraConfig = lib.mkIf userCfg.tmux.enable ''
        bind-key l run-shell '${tmux-lazygit}/bin/tmux-lazygit'
      '';

      programs.lazygit = {
        enable = true;
        settings = {
          customCommands = [
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
