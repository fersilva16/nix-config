{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  # prefix+l toggles a lazygit popup, one per tmux session, replacing tmux's
  # last-window. Like pocket (tmux/pocket.nix), lazygit lives in a hidden
  # background session that the popup attaches to, so closing the popup only
  # detaches: the next prefix+l comes back to the same view, selection and
  # scroll position. Quitting lazygit (q) ends the hidden session; the next
  # toggle starts a fresh one.
  #
  # The hidden session is keyed by the parent's session_id, not its name, so
  # a wtmv rename keeps its popup. Its name starts with "_", which the session
  # pickers skip (tmux.nix). It starts at / rather than the repo because
  # wts, oc-search and omo's agent find a worktree's session by session_path,
  # and a popup session started in the worktree would win that lookup.
  #
  # lazygit runs through a LOGIN fish, not the bare binary. A command passed
  # to new-session is exec'd from the tmux server's environment, which is
  # whatever the server was launched with: here /usr/bin:/bin and the tmux
  # store path, no ~/.nix-profile/bin. A bare `lazygit` is not found, the
  # pane dies before it draws, and the popup opens and instantly closes. An
  # absolute store path would fix launching but not the customCommands below,
  # which shell out to fish and gh and would inherit that same stripped PATH.
  # The login shell fixes both, and its cd puts lazygit in the repo.
  tmux-lazygit = pkgs.writeShellApplication {
    name = "tmux-lazygit";
    runtimeInputs = [ pkgs.tmux ];
    text = ''
      # Inside the popup: detach, which exits the popup's `tmux attach` client
      # and so closes the popup, leaving lazygit running.
      case "$(tmux display-message -p '#S')" in
      _lazygit-*) exec tmux detach-client ;;
      esac

      # A killed parent session (wtrm, kill-session) leaves its popup session
      # behind, hidden from every picker. Reap those here.
      tmux list-sessions -F '#{session_name}' | while read -r s; do
        case "$s" in
        _lazygit-*) tmux has-session -t "\$''${s#_lazygit-}" 2>/dev/null || tmux kill-session -t "=$s" ;;
        esac
      done

      id=$(tmux display-message -p '#{session_id}')
      hidden="_lazygit-''${id#\$}"
      if ! tmux has-session -t "=$hidden" 2>/dev/null; then
        path=$(tmux display-message -p '#{pane_current_path}')
        # $argv is fish's, expanded by fish rather than here.
        # shellcheck disable=SC2016
        tmux new-session -d -s "$hidden" -c / \
          ${pkgs.fish}/bin/fish -lc 'cd $argv[1]; and exec lazygit' "$path"
        tmux set-option -t "=$hidden" status off
      fi
      exec tmux display-popup -E -w 90% -h 90% "tmux attach -t =$hidden"
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
