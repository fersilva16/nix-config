{ pkgs }:
let
  tmux-remote = pkgs.writeShellApplication {
    name = "tmux-remote";
    bashOptions = [ ];
    runtimeInputs = [ pkgs.tmux ];
    text = builtins.readFile ./scripts/remote.sh;
  };

  tmux-ssh-widget = pkgs.writeShellApplication {
    name = "tmux-ssh-widget";
    bashOptions = [ ];
    text = ''
      BG="#f2f0e5"
      FG="#100f0f"
      RED="#d14d41"
      RESET="#[fg=''${FG},bg=''${BG},nobold,noitalics,nounderscore,nodim]"
      echo "#[fg=''${RED},bg=''${BG},bold] SSH''${RESET}"
    '';
  };

  tmux-battery-widget = pkgs.writeShellApplication {
    name = "tmux-battery-widget";
    bashOptions = [ ];
    text = ''
      # Flexoki light theme colors
      BG="#f2f0e5"
      FG="#100f0f"
      RED="#d14d41"
      GREEN="#879a39"
      YELLOW="#d0a215"
      ORANGE="#da702c"

      RESET="#[fg=''${FG},bg=''${BG},nobold,noitalics,nounderscore,nodim]"

      info=$(pmset -g batt 2>/dev/null)
      [[ -z "$info" ]] && exit 0

      percent=$(echo "$info" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
      [[ -z "$percent" ]] && exit 0

      charging=""
      if echo "$info" | grep -q "AC Power"; then
        charging="+"
      elif echo "$info" | grep -q "charged"; then
        charging="+"
      fi

      if [[ "$percent" -ge 80 ]]; then
        color="$GREEN"
      elif [[ "$percent" -ge 60 ]]; then
        color="$GREEN"
      elif [[ "$percent" -ge 40 ]]; then
        color="$YELLOW"
      elif [[ "$percent" -ge 20 ]]; then
        color="$ORANGE"
      else
        color="$RED"
      fi

      label="''${charging:+''${charging} }''${percent}%"
      echo "#[fg=''${color},bg=''${BG},bold] ''${label}''${RESET}"
    '';
  };
in
{
  home = {
    home.packages = [
      tmux-remote
      tmux-ssh-widget
      tmux-battery-widget
    ];

    # Register widgets for remote mode (ordered by filename prefix)
    xdg.configFile."tmux/widgets-remote/50-ssh" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        exec ${tmux-ssh-widget}/bin/tmux-ssh-widget
      '';
    };
    xdg.configFile."tmux/widgets-remote/60-battery" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        exec ${tmux-battery-widget}/bin/tmux-battery-widget
      '';
    };

    programs.tmux.extraConfig = ''
      # Remote access mode: prefix + M-r to toggle (SSH + lid-close safe + battery saving)
      bind-key 'M-r' run-shell "${tmux-remote}/bin/tmux-remote toggle"
    '';
  };
}
