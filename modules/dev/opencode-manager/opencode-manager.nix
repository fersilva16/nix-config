{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  jsonFormat = pkgs.formats.json { };

  tmux-git-root-path = pkgs.writeShellApplication {
    name = "tmux-git-root-path";
    runtimeInputs = [ pkgs.git ];
    text = ''
      dir="''${1:-.}"
      cd "$dir" && git rev-parse --show-toplevel 2>/dev/null || echo "$dir"
    '';
  };

  tmux-opencode-manager = pkgs.writeShellApplication {
    name = "tmux-opencode-manager";
    bashOptions = [ ];
    excludeShellChecks = [
      "SC2154"
      "SC2329"
    ];
    runtimeInputs = [
      pkgs.argc
      pkgs.fswatch
      pkgs.jq
      pkgs.sqlite
      pkgs.tmux
      pkgs.coreutils
      pkgs.gawk
      pkgs.ncurses
    ];
    text = builtins.readFile ./scripts/opencode-manager.sh;
  };

  tmux-spawn-agent = pkgs.writeShellApplication {
    name = "tmux-spawn-agent";
    runtimeInputs = [
      pkgs.tmux
      tmux-git-root-path
    ];
    text = ''
      set -eu

      PANE_PATH="$1"
      shift
      PROMPT="$*"

      if [[ -z "$PROMPT" ]]; then
        tmux display-message "spawn-agent: no prompt provided"
        exit 1
      fi

      GIT_ROOT=$(tmux-git-root-path "$PANE_PATH")
      SESSION=$(tmux display-message -p '#S')
      AGENTS_WINDOW="agents"
      TARGET="$SESSION:$AGENTS_WINDOW"

      # printf %q shell-quotes the prompt so it survives tmux's sh -c execution
      SAFE_PROMPT=$(printf '%q' "$PROMPT")

      if ! tmux list-windows -t "$SESSION" -F '#W' | grep -q "^''${AGENTS_WINDOW}$"; then
        tmux new-window -t "$SESSION" -n "$AGENTS_WINDOW" -c "$GIT_ROOT" "opencode run ''${SAFE_PROMPT}"
        tmux set-option -w -t "$TARGET" remain-on-exit on
      else
        tmux split-window -t "$TARGET" -c "$GIT_ROOT" "opencode run ''${SAFE_PROMPT}"
        tmux select-layout -t "$TARGET" tiled
      fi

      tmux select-window -t "$TARGET"
    '';
  };

  tmux-agent-prompt = pkgs.writeShellApplication {
    name = "tmux-agent-prompt";
    bashOptions = [ ];
    runtimeInputs = [ tmux-spawn-agent ];
    text = ''
      set -eu
      trap 'exit 0' INT

      PANE_PATH="$1"

      printf ' 󰚩 agent: '

      PROMPT=""
      while IFS= read -rsn1 char; do
        if [[ "$char" == $'\e' ]]; then
          read -rsn5 -t 0.01 _ 2>/dev/null || true
          exit 0
        fi

        [[ "$char" == "" ]] && break

        if [[ "$char" == $'\x7f' || "$char" == $'\b' ]]; then
          if [[ -n "$PROMPT" ]]; then
            PROMPT="''${PROMPT%?}"
            printf '\b \b'
          fi
          continue
        fi

        PROMPT+="$char"
        printf '%s' "$char"
      done

      [[ -z "$PROMPT" ]] && exit 0

      printf '\n'
      exec tmux-spawn-agent "$PANE_PATH" "$PROMPT"
    '';
  };
in
mkUserModule {
  name = "opencode-manager";
  requires = [
    "tmux"
    "opencode"
  ];
  home = {
    home.packages = [
      tmux-opencode-manager
      tmux-spawn-agent
      tmux-agent-prompt
    ];

    xdg.configFile = {
      "tmux/widgets/10-notify" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          exec ${tmux-opencode-manager}/bin/tmux-opencode-manager widget
        '';
      };

      "tmux/widgets-remote/10-notify" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          exec ${tmux-opencode-manager}/bin/tmux-opencode-manager widget --plain
        '';
      };

      "opencode/plugins/pane-mapping.ts".source = ./plugins/pane-mapping.ts;

      "opencode/opencode-notifier.json".source = jsonFormat.generate "opencode-notifier.json" {
        sound = true;
        notification = false;
        suppressWhenFocused = false;
        command = {
          enabled = true;
          path = "${tmux-opencode-manager}/bin/tmux-opencode-manager";
          args = [
            "notify"
            "add"
            "--event"
            "{event}"
            "{message}"
          ];
          minDuration = 0;
        };
      };
    };

    programs.tmux.extraConfig = ''
      bind-key 'n' display-popup -w 80 -h 30 -E "${tmux-opencode-manager}/bin/tmux-opencode-manager tui"
      bind-key 'N' run-shell "${tmux-opencode-manager}/bin/tmux-opencode-manager notify goto"
      set-hook -g after-select-window 'run-shell -b "${tmux-opencode-manager}/bin/tmux-opencode-manager notify auto-dismiss"'
      set-hook -g client-session-changed 'run-shell -b "${tmux-opencode-manager}/bin/tmux-opencode-manager notify auto-dismiss"'
      set-hook -g pane-exited 'run-shell -b "${tmux-opencode-manager}/bin/tmux-opencode-manager notify dismiss-target #{session_name}:#{window_index}; ${tmux-opencode-manager}/bin/tmux-opencode-manager refresh"'
      set-hook -g session-closed 'run-shell -b "${tmux-opencode-manager}/bin/tmux-opencode-manager notify dismiss-session #{session_name}"'
      set-hook -g after-split-window 'run-shell -b "${tmux-opencode-manager}/bin/tmux-opencode-manager refresh"'
      set-hook -g after-new-window 'run-shell -b "${tmux-opencode-manager}/bin/tmux-opencode-manager refresh"'
      bind-key 'a' display-popup -E -h 3 -w 60% -s 'bg=default' -S 'bg=default' "${tmux-agent-prompt}/bin/tmux-agent-prompt '#{pane_current_path}'"
    '';
  };
}
