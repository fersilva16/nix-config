{ pkgs }:
let
  tmux-group = pkgs.writeShellApplication {
    name = "tmux-group";
    runtimeInputs = [ pkgs.tmux ];
    text = ''
      SESSION=$(tmux display-message -p "#{session_name}")

      # Don't group an already grouped session — use its parent instead
      if [[ "$SESSION" =~ _g[0-9]+$ ]]; then
        SESSION="''${SESSION%_g[0-9]*}"
      fi

      # Find next available group ID
      id=1
      while tmux has-session -t "''${SESSION}_g''${id}" 2>/dev/null; do
        id=$((id + 1))
      done

      GROUP_SESSION="''${SESSION}_g''${id}"

      # Open a new Ghostty window that creates the grouped session.
      # destroy-unattached ensures cleanup when the window closes.
      open -na Ghostty --args -e tmux new-session -t "$SESSION" -s "$GROUP_SESSION" \; \
        set-option destroy-unattached on
    '';
  };

  tmux-ungroup = pkgs.writeShellApplication {
    name = "tmux-ungroup";
    runtimeInputs = [ pkgs.tmux ];
    text = ''
      SESSION=$(tmux display-message -p "#{session_name}")

      if [[ ! "$SESSION" =~ _g[0-9]+$ ]]; then
        tmux display-message "Not in a grouped session"
        exit 0
      fi

      # Kill this grouped session — tmux will close the client (and Ghostty window)
      tmux kill-session -t "$SESSION"
    '';
  };
in
{
  home = {
    home.packages = [
      tmux-group
      tmux-ungroup
    ];
    programs.tmux.extraConfig = ''
      # Group session (multi-monitor): prefix + g to create, prefix + G to leave
      bind-key 'g' run-shell "${tmux-group}/bin/tmux-group"
      bind-key 'G' run-shell "${tmux-ungroup}/bin/tmux-ungroup"
    '';
  };
}
