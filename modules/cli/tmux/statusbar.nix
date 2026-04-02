{ pkgs }:
let
  tmux-git-status = pkgs.writeShellApplication {
    name = "tmux-git-status";
    bashOptions = [ ];
    runtimeInputs = [
      pkgs.git
      pkgs.coreutils
    ];
    text = builtins.readFile ./scripts/git-status.sh;
  };

  tmux-path-widget = pkgs.writeShellApplication {
    name = "tmux-path-widget";
    bashOptions = [ ];
    runtimeInputs = [ pkgs.tmux ];
    text = ''
      # Flexoki light theme colors
      BG="#f2f0e5"
      FG="#100f0f"
      BLUE="#4385be"

      RESET="#[fg=''${FG},bg=''${BG},nobold,noitalics,nounderscore,nodim]"

      SHOW_PATH=$(tmux show-option -gv @flexoki-tmux_show_path 2>/dev/null || true)
      PATH_FORMAT=$(tmux show-option -gv @flexoki-tmux_path_format 2>/dev/null || true)

      # Enabled by default; set @flexoki-tmux_show_path to "0" to disable
      if [ "''${SHOW_PATH}" = "0" ]; then
        exit 0
      fi

      current_path="''${1}"
      PATH_FORMAT="''${PATH_FORMAT:-relative}"

      if [[ ''${PATH_FORMAT} == "relative" ]]; then
        home_dir="''${HOME:-$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $2}')}"
        home_dir="''${home_dir:-/Users/$(id -un)}"
        current_path="''${current_path/#''${home_dir}/\~}"
      fi

      echo "#[fg=''${BLUE},bg=''${BG}]  ''${RESET}''${current_path} "
    '';
  };

  # Composable status bar orchestrator.
  # Scans ~/.config/tmux/widgets/ (normal) or ~/.config/tmux/widgets-remote/ (remote)
  # and runs every executable in filename order. Each part registers its own widgets.
  tmux-status-right = pkgs.writeShellApplication {
    name = "tmux-status-right";
    bashOptions = [ ];
    text = ''
      WIDGETS_DIR="$HOME/.config/tmux/widgets"
      WIDGETS_REMOTE_DIR="$HOME/.config/tmux/widgets-remote"
      STATE_FILE="/tmp/tmux-remote-state"
      PANE_PATH="''${1:-}"

      if [[ -f "$STATE_FILE" ]]; then
        DIR="$WIDGETS_REMOTE_DIR"
      else
        DIR="$WIDGETS_DIR"
      fi

      OUTPUT=""
      if [[ -d "$DIR" ]]; then
        for widget in "$DIR"/*; do
          [[ -x "$widget" ]] || continue
          result=$("$widget" "$PANE_PATH" 2>/dev/null || true)
          OUTPUT+="$result"
        done
      fi
      echo "$OUTPUT"
    '';
  };
in
{
  home = {
    home.packages = [
      tmux-status-right
      tmux-git-status
      tmux-path-widget
    ];

    # Register widgets for normal mode (ordered by filename prefix)
    xdg.configFile."tmux/widgets/50-path" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        exec ${tmux-path-widget}/bin/tmux-path-widget "$@"
      '';
    };
    xdg.configFile."tmux/widgets/60-git" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        exec ${tmux-git-status}/bin/tmux-git-status "$@"
      '';
    };

    programs.tmux.extraConfig = ''
      # Status bar right side — composable orchestrator scans widget directories
      set -g status-right "#(${tmux-status-right}/bin/tmux-status-right #{pane_current_path})"
      set -g status-right-length 200
    '';
  };
}
