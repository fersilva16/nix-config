{ pkgs }:
let
  tmux-cpu-widget = pkgs.writeShellApplication {
    name = "tmux-cpu-widget";
    bashOptions = [ ];
    text = ''
      # Flexoki light theme colors
      BG="#f2f0e5"
      FG="#100f0f"
      GREEN="#879a39"
      YELLOW="#d0a215"
      ORANGE="#da702c"
      RED="#d14d41"

      RESET="#[fg=''${FG},bg=''${BG},nobold,noitalics,nounderscore,nodim]"

      # Instantaneous CPU usage from top (-l 1 = single sample, -n 0 = no process list).
      # After stripping %, the line tokenises as:
      #   $1=CPU $2=usage: $3=user% $4=user, $5=sys% $6=sys, $7=idle% $8=idle
      cpu=$(top -l 1 -n 0 2>/dev/null | awk '/CPU usage/ { gsub(/%/, ""); printf "%.0f", $3 + $5 }')
      [[ -z "''${cpu}" ]] && exit 0

      if (( cpu < 30 )); then
        color="''${GREEN}"
      elif (( cpu < 60 )); then
        color="''${YELLOW}"
      elif (( cpu < 85 )); then
        color="''${ORANGE}"
      else
        color="''${RED}"
      fi

      echo "#[fg=''${color},bg=''${BG},bold]  ''${cpu}%''${RESET} "
    '';
  };

  tmux-memory-widget = pkgs.writeShellApplication {
    name = "tmux-memory-widget";
    bashOptions = [ ];
    text = ''
      # Flexoki light theme colors
      BG="#f2f0e5"
      FG="#100f0f"
      GREEN="#879a39"
      YELLOW="#d0a215"
      ORANGE="#da702c"
      RED="#d14d41"

      RESET="#[fg=''${FG},bg=''${BG},nobold,noitalics,nounderscore,nodim]"

      # Memory usage derived from top's PhysMem line, e.g.:
      #   "PhysMem: 60G used (3055M wired, 3527M compressor), 3915M unused."
      phys=$(top -l 1 -n 0 2>/dev/null | awk '/^PhysMem:/ { print; exit }')
      [[ -z "''${phys}" ]] && exit 0

      used=$(echo "''${phys}" | sed -nE 's/^PhysMem: +([0-9]+)([GMK]) used.*/\1 \2/p')
      unused=$(echo "''${phys}" | sed -nE 's/.*, ([0-9]+)([GMK]) unused.*/\1 \2/p')
      [[ -z "''${used}" || -z "''${unused}" ]] && exit 0

      to_mb() {
        local num unit
        read -r num unit <<< "$1"
        case "''${unit}" in
          G) echo $(( num * 1024 )) ;;
          M) echo "''${num}" ;;
          K) echo $(( num / 1024 )) ;;
          *) echo 0 ;;
        esac
      }

      used_mb=$(to_mb "''${used}")
      unused_mb=$(to_mb "''${unused}")
      total_mb=$(( used_mb + unused_mb ))
      (( total_mb == 0 )) && exit 0
      pct=$(( used_mb * 100 / total_mb ))

      if (( pct < 60 )); then
        color="''${GREEN}"
      elif (( pct < 75 )); then
        color="''${YELLOW}"
      elif (( pct < 90 )); then
        color="''${ORANGE}"
      else
        color="''${RED}"
      fi

      echo "#[fg=''${color},bg=''${BG},bold]  ''${pct}%''${RESET} "
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
      tmux-cpu-widget
      tmux-memory-widget
    ];

    # Register widgets for normal mode (ordered by filename prefix)
    xdg.configFile."tmux/widgets/50-cpu" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        exec ${tmux-cpu-widget}/bin/tmux-cpu-widget "$@"
      '';
    };
    xdg.configFile."tmux/widgets/60-memory" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        exec ${tmux-memory-widget}/bin/tmux-memory-widget "$@"
      '';
    };

    programs.tmux.extraConfig = ''
      # Status bar right side — composable orchestrator scans widget directories
      set -g status-right "#(${tmux-status-right}/bin/tmux-status-right #{pane_current_path})"
      set -g status-right-length 200
    '';
  };
}
