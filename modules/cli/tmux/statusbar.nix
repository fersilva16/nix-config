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

      # 1-minute load average as a percentage of available cores. macOS exposes
      # no cheap instantaneous CPU%: top -l 1 costs ~1.2s and iostat -c 2 ~1.0s,
      # both far too slow for a 5s status interval. vm.loadavg is ~18ms.
      # ponytail: load counts runnable + uninterruptible tasks, so this reads a
      # little higher than top's user+sys and can exceed 100%.
      ncpu=$(sysctl -n hw.ncpu 2>/dev/null)
      cpu=$(sysctl -n vm.loadavg 2>/dev/null | awk -v n="''${ncpu:-1}" '{ printf "%.0f", $2 / n * 100 }')
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

  tmux-disk-widget = pkgs.writeShellApplication {
    name = "tmux-disk-widget";
    bashOptions = [ ];
    text = ''
      # Flexoki light theme colors
      BG="#f2f0e5"
      FG="#100f0f"
      YELLOW="#d0a215"
      ORANGE="#da702c"
      RED="#d14d41"

      RESET="#[fg=''${FG},bg=''${BG},nobold,noitalics,nounderscore,nodim]"

      # df -k is ~5ms; the APFS container reports slightly more free than this
      # (purgeable space), so the widget errs on the pessimistic side.
      free=$(df -k / 2>/dev/null | awk 'NR==2 { printf "%d", $4 / 1048576 }')
      [[ -z "''${free}" ]] && exit 0

      # Silent above 100G. A widget that is always visible is a widget you stop
      # seeing, and the point of this one is to be noticed exactly once.
      # 25G is where nix.settings.min-free starts collecting garbage mid-build.
      if (( free >= 100 )); then
        exit 0
      elif (( free >= 50 )); then
        color="''${YELLOW}"
      elif (( free >= 25 )); then
        color="''${ORANGE}"
      else
        color="''${RED}"
      fi

      echo "#[fg=''${color},bg=''${BG},bold]  ''${free}G''${RESET} "
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
      tmux-disk-widget
    ];

    # Register widgets for normal mode (ordered by filename prefix)
    xdg.configFile."tmux/widgets/50-cpu" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        exec ${tmux-cpu-widget}/bin/tmux-cpu-widget "$@"
      '';
    };

    xdg.configFile."tmux/widgets/55-disk" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        exec ${tmux-disk-widget}/bin/tmux-disk-widget "$@"
      '';
    };

    programs.tmux.extraConfig = ''
      # Status bar right side — composable orchestrator scans widget directories
      set -g status-right "#(${tmux-status-right}/bin/tmux-status-right #{pane_current_path})"
      set -g status-right-length 200
    '';
  };
}
