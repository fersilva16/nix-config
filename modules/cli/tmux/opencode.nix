{
  pkgs,
  lib,
  tmux-git-root-path,
}:
let
  jsonFormat = pkgs.formats.json { };

  tmux-opencode-generating = pkgs.writeShellApplication {
    name = "tmux-opencode-generating";
    bashOptions = [ ];
    runtimeInputs = [
      pkgs.sqlite
      pkgs.tmux
      pkgs.coreutils
      pkgs.jq
      pkgs.gawk
    ];
    text = ''
      set -u

      OPENCODE_DB="''${HOME}/.local/share/opencode/opencode-local.db"

      if [[ ! -f "$OPENCODE_DB" ]] || ! command -v sqlite3 &>/dev/null || ! command -v tmux &>/dev/null; then
        echo '[]'
        exit 0
      fi

      panes=$(tmux list-panes -a -F '#{session_name} #{window_index} #{pane_current_command} #{pane_current_path}' 2>/dev/null | \
        awk '/opencode/ {print $1, $2, $4}' | sort -u)

      if [[ -z "$panes" ]]; then
        echo '[]'
        exit 0
      fi

      # Directories with an assistant message still streaming (time.completed is null).
      # Capped at 2 hours to skip stale entries from crashed sessions.
      query="SELECT DISTINCT s.directory FROM message m
        JOIN session s ON m.session_id = s.id
        WHERE json_extract(m.data, '\$.role') = 'assistant'
          AND (json_extract(m.data, '\$.time.completed') IS NULL
               OR json_extract(m.data, '\$.time.completed') = '''')
          AND m.time_created > ((strftime('%s', 'now') - 7200) * 1000)"

      gen_dirs=$(sqlite3 "$OPENCODE_DB" "$query" 2>/dev/null)

      if [[ -z "$gen_dirs" ]]; then
        echo '[]'
        exit 0
      fi

      matched=""
      while IFS=' ' read -r sess win path; do
        if echo "$gen_dirs" | grep -qxF "$path"; then
          matched+="''${sess} ''${win}"$'\n'
        fi
      done <<< "$panes"

      if [[ -z "''${matched:-}" ]]; then
        echo '[]'
        exit 0
      fi

      echo "$matched" | awk 'NF {printf "%s %s\n", $1, $2}' | \
        jq -Rn '[inputs | split(" ") | {session: .[0], target: (.[0] + ":" + .[1])}]'
    '';
  };

  tmux-notify = pkgs.writeShellApplication {
    name = "tmux-notify";
    bashOptions = [ ];
    runtimeInputs = [
      pkgs.jq
      pkgs.coreutils
      pkgs.tmux
    ];
    text = builtins.readFile ./scripts/notify.sh;
  };

  tmux-notify-widget = pkgs.writeShellApplication {
    name = "tmux-notify-widget";
    bashOptions = [ ];
    runtimeInputs = [
      pkgs.jq
      pkgs.coreutils
      tmux-opencode-generating
    ];
    text = ''
      # tmux-notify-widget: Status bar widget showing generating opencode count and notification count.

      NOTIFY_FILE="''${TMUX_NOTIFY_FILE:-/tmp/tmux-notifications.json}"

      BG="#f2f0e5"
      FG="#100f0f"
      ORANGE="#da702c"
      GREEN="#879a39"

      RESET="#[fg=''${FG},bg=''${BG},nobold,noitalics,nounderscore,nodim]"

      ACTIVE=$(tmux-opencode-generating 2>/dev/null || echo '[]')
      ACTIVE=$(echo "$ACTIVE" | jq 'length' 2>/dev/null || echo 0)

      NOTIFS=0
      if [[ -f "$NOTIFY_FILE" ]]; then
        NOTIFS=$(jq 'length' "$NOTIFY_FILE" 2>/dev/null || echo 0)
      fi

      OUTPUT=""

      if [[ "$ACTIVE" -gt 0 ]]; then
        if [[ "''${1:-}" == "--plain" ]]; then
          OUTPUT="G:''${ACTIVE}"
        else
          OUTPUT="#[fg=''${GREEN},bg=''${BG},bold] ⏳ ''${ACTIVE}''${RESET}"
        fi
      fi

      if [[ "$NOTIFS" -gt 0 ]]; then
        if [[ "''${1:-}" == "--plain" ]]; then
          OUTPUT="''${OUTPUT} !''${NOTIFS}"
        else
          OUTPUT="''${OUTPUT}#[fg=''${ORANGE},bg=''${BG},bold] 󰂞 ''${NOTIFS}''${RESET}"
        fi
      fi

      echo "$OUTPUT"
    '';
  };

  tmux-opencode-manager = pkgs.writeShellApplication {
    name = "tmux-opencode-manager";
    bashOptions = [ ];
    runtimeInputs = [
      pkgs.jq
      pkgs.ncurses
      pkgs.tmux
      tmux-opencode-generating
      tmux-notify
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
{
  home =
    { userCfg, ... }:
    {
      home.packages = [
        tmux-notify
        tmux-notify-widget
        tmux-opencode-generating
        tmux-opencode-manager
        tmux-spawn-agent
        tmux-agent-prompt
      ];

      xdg.configFile = {
        # Register notification widget for normal mode
        "tmux/widgets/10-notify" = {
          executable = true;
          text = ''
            #!/usr/bin/env bash
            exec ${tmux-notify-widget}/bin/tmux-notify-widget
          '';
        };

        # Register notification widget for remote mode (plain output)
        "tmux/widgets-remote/10-notify" = {
          executable = true;
          text = ''
            #!/usr/bin/env bash
            exec ${tmux-notify-widget}/bin/tmux-notify-widget --plain
          '';
        };

        # Outbound: configure opencode notifier when opencode is enabled
        "opencode/opencode-notifier.json" = lib.mkIf userCfg.opencode.enable {
          source = jsonFormat.generate "opencode-notifier.json" {
            sound = true;
            notification = false;
            suppressWhenFocused = false;
            command = {
              enabled = true;
              path = "${tmux-notify}/bin/tmux-notify";
              args = [
                "add"
                "--event"
                "{event}"
                "{message}"
              ];
              minDuration = 0;
            };
          };
        };
      };

      programs.tmux.extraConfig = ''
        # Notification panel on prefix + n
        bind-key 'n' display-popup -w 60 -h 20 -E "${tmux-opencode-manager}/bin/tmux-opencode-manager"

        # Jump to last notification on prefix + N
        bind-key 'N' run-shell "${tmux-notify}/bin/tmux-notify goto"

        # Auto-dismiss notifications when switching to their window
        set-hook -g after-select-window 'run-shell -b "${tmux-notify}/bin/tmux-notify auto-dismiss"'

        # Spawn opencode agent in dedicated "agents" window (prefix + a opens prompt bar)
        bind-key 'a' display-popup -E -h 3 -w 60% -s 'bg=default' -S 'bg=default' "${tmux-agent-prompt}/bin/tmux-agent-prompt '#{pane_current_path}'"
      '';
    };
}
