{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  mohak34-sounds = pkgs.stdenvNoCC.mkDerivation {
    pname = "mohak34-opencode-notifier-sounds";
    version = "0.1.36";
    src = pkgs.fetchFromGitHub {
      owner = "mohak34";
      repo = "opencode-notifier";
      rev = "v0.1.36";
      sha256 = "sha256-tjxaqh9akN81MMToeGG1wNEiTp0/WEOmatmXewCThWU=";
    };
    dontBuild = true;
    installPhase = ''
      mkdir -p $out
      cp sounds/*.wav $out/
    '';
  };

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

  # Resolve a tmux pane's opencode session ID.
  # Reads @oc-sid from tmux pane options (set by the wrapper sidecar),
  # falls back to DB query by directory.
  # Exit 0 + stdout: session ID
  # Exit 1: no mapping found
  # Exit 2: pending (session not yet resolved — caller should retry)
  # Usage: tmux-opencode-session <pane_id> [pane_path]
  tmux-opencode-session = pkgs.writeShellApplication {
    name = "tmux-opencode-session";
    runtimeInputs = [
      pkgs.sqlite
      pkgs.tmux
      tmux-git-root-path
    ];
    text = ''
      set -eu

      PANE_ID="''${1:?usage: tmux-opencode-session <pane_id> [pane_path]}"
      PANE_PATH="''${2:-}"

      # Primary: tmux pane option (set by the wrapper SSE sidecar)
      STATUS=$(tmux show-options -pv -t "$PANE_ID" @oc-status 2>/dev/null || true)
      case "$STATUS" in
        active)
          SID=$(tmux show-options -pv -t "$PANE_ID" @oc-sid 2>/dev/null || true)
          if [[ -n "$SID" ]]; then
            echo "$SID"
            exit 0
          fi
          ;;
        pending)
          exit 2
          ;;
      esac

      # Fallback: DB query by directory (for legacy or non-wrapper panes)
      if [[ -z "$PANE_PATH" ]]; then
        PANE_PATH=$(tmux display-message -p -t "$PANE_ID" '#{pane_current_path}' 2>/dev/null || true)
      fi
      [[ -z "$PANE_PATH" ]] && exit 1

      OPENCODE_DB="$HOME/.local/share/opencode/opencode-local.db"
      [[ ! -f "$OPENCODE_DB" ]] && exit 1

      GIT_ROOT=$(tmux-git-root-path "$PANE_PATH")
      SID=$(sqlite3 "$OPENCODE_DB" \
        "SELECT id FROM session WHERE directory = '$GIT_ROOT'
         ORDER BY time_updated DESC LIMIT 1" 2>/dev/null || true)

      if [[ -z "''${SID:-}" ]]; then
        exit 1
      fi

      echo "$SID"
    '';
  };

  tmux-opencode-fork-window = pkgs.writeShellApplication {
    name = "tmux-opencode-fork-window";
    runtimeInputs = [
      pkgs.tmux
      tmux-git-root-path
      tmux-opencode-session
    ];
    text = ''
      set -eu

      PANE_ID="$1"
      PANE_PATH="$2"

      SESSION_ID=""
      for _ in 1 2 3 4 5; do
        SESSION_ID=$(tmux-opencode-session "$PANE_ID" "$PANE_PATH") && break
        rc=$?
        if [[ $rc -eq 2 ]]; then sleep 0.5; else exit 1; fi
      done
      [[ -z "$SESSION_ID" ]] && exit 1

      GIT_ROOT=$(tmux-git-root-path "$PANE_PATH")
      TMUX_SESSION=$(tmux display-message -p '#S')

      tmux new-window -t "$TMUX_SESSION" -c "$GIT_ROOT" "opencode --session $SESSION_ID --fork"
    '';
  };

  tmux-oc-sync-sid = pkgs.writeShellApplication {
    name = "tmux-oc-sync-sid";
    runtimeInputs = [
      pkgs.gnugrep
      pkgs.gnused
      pkgs.sqlite
      pkgs.tmux
    ];
    text = builtins.readFile ./scripts/oc-sync-sid.sh;
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
      tmux-opencode-session
      tmux-opencode-fork-window
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

      "opencode/plugin/tmux-notifier.ts".source = ./plugins/tmux-notifier.ts;
    };

    home.sessionVariables.OPENCODE_TMUX_NOTIFIER_SOUND_DIR = "${mohak34-sounds}";

    programs.tmux.extraConfig = ''
      bind-key 'n' run-shell "tmux display-popup -w 80 -h 30 -E -e TMUX_OPENCODE_CALLER_TTY='#{client_tty}' ${tmux-opencode-manager}/bin/tmux-opencode-manager tui"
      bind-key 'N' run-shell -b "env TMUX_OPENCODE_CALLER_TTY='#{client_tty}' ${tmux-opencode-manager}/bin/tmux-opencode-manager notify goto"
      set-hook -g after-select-window 'run-shell -b "${tmux-opencode-manager}/bin/tmux-opencode-manager notify dismiss-target #{session_name}:#{window_index}"'
      set-hook -g client-session-changed 'run-shell -b "${tmux-opencode-manager}/bin/tmux-opencode-manager notify dismiss-target #{session_name}:#{window_index}"'
      set-hook -g after-kill-pane 'run-shell -b "${tmux-opencode-manager}/bin/tmux-opencode-manager notify dismiss-pane \"#{hook_arguments}\"; ${tmux-opencode-manager}/bin/tmux-opencode-manager refresh"'
      set-hook -g window-unlinked 'run-shell -b "${tmux-opencode-manager}/bin/tmux-opencode-manager refresh"'
      set-hook -g session-closed 'run-shell -b "${tmux-opencode-manager}/bin/tmux-opencode-manager notify dismiss-session #{session_name}"'
      set-hook -g pane-title-changed 'run-shell -b "${tmux-oc-sync-sid}/bin/tmux-oc-sync-sid #{pane_id}"'
      set-hook -g after-split-window 'run-shell -b "${tmux-opencode-manager}/bin/tmux-opencode-manager refresh"'
      set-hook -g after-new-window 'run-shell -b "${tmux-opencode-manager}/bin/tmux-opencode-manager refresh"'
      bind-key 'a' display-popup -E -h 3 -w 60% -s 'bg=default' -S 'bg=default' "${tmux-agent-prompt}/bin/tmux-agent-prompt '#{pane_current_path}'"
      bind-key 'f' run-shell "${tmux-opencode-fork-window}/bin/tmux-opencode-fork-window '#{pane_id}' '#{pane_current_path}'"
    '';
  };
}
