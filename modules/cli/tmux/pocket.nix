{ pkgs }:
let
  # Pocket terminal: a persistent background tmux session overlaid as a popup.
  # Quake-style drop-down — toggle with prefix+p from anywhere, contents
  # survive between toggles (shell history, running processes, scrollback).
  #
  # Smart toggle: if the current client is already attached to the pocket
  # session (i.e. we're inside the popup), detach to close it. Otherwise
  # open the popup. The pocket session is reserved for this use — manually
  # attaching to it would cause prefix+p to detach you, which is acceptable.
  tmux-pocket = pkgs.writeShellApplication {
    name = "tmux-pocket";
    runtimeInputs = [ pkgs.tmux ];
    text = ''
      SESSION=pocket

      # If current client is inside the pocket session, close the popup
      # by detaching. Works because the popup was spawned with `tmux attach`,
      # so detach exits that inner client and `display-popup -E` closes.
      CURRENT=$(tmux display-message -p '#S' 2>/dev/null || true)
      if [ "$CURRENT" = "$SESSION" ]; then
        exec tmux detach-client
      fi

      # Ensure the pocket session exists, rooted at $HOME for general use.
      if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        tmux new-session -d -s "$SESSION" -c "$HOME"
      fi

      exec tmux display-popup -E -w 90% -h 90% "tmux attach -t $SESSION"
    '';
  };
in
{
  home = {
    home.packages = [ tmux-pocket ];
    programs.tmux.extraConfig = ''
      # Pocket terminal: Quake-style popup with a persistent background shell.
      # Meant for long-lived TUI agents (opencode, claude, aider) in windows
      # that survive between toggles. Bound prefix-free to Alt+backtick
      # (Quake tradition) — one chord, fast re-entry. `-n` skips the prefix.
      #
      # The picker bind (`bind-key s`) lives in tmux.nix with a defensive
      # pocket filter, avoiding part/parent extraConfig merge-order dependency.
      bind-key -n M-` run-shell '${tmux-pocket}/bin/tmux-pocket'
    '';
  };
}
