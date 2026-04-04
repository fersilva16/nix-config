{
  pkgs,
  opencode-unwrapped,
  serverPort,
}:
let
  serverUrl = "http://127.0.0.1:${toString serverPort}";

  # Wrapper that auto-attaches TUI clients and `run` commands to the
  # shared server managed by the launchd agent.  Falls back to normal
  # (standalone) behaviour when the server is unreachable.
  opencode-wrapper = pkgs.writeShellScriptBin "opencode" ''
    REAL="${opencode-unwrapped}/bin/opencode"
    URL="${serverUrl}"

    # Near-instant port check (no HTTP overhead)
    server_up() {
      exec 3<>/dev/tcp/127.0.0.1/${toString serverPort} 2>/dev/null
      local rc=$?
      exec 3>&- 2>/dev/null
      return $rc
    }

    LABEL="com.opencode.server"
    UID_VAL=$(id -u)

    # Start the server if it isn't running, recovering stale launchd
    # registrations when needed.  Returns 0 once the port is up.
    ensure_server() {
      server_up && return 0

      if ! launchctl bootstrap "gui/$UID_VAL" "$HOME/Library/LaunchAgents/$LABEL.plist" 2>/dev/null; then
        # Stale registration (crashed but still registered) — auto-recover
        launchctl bootout "gui/$UID_VAL/$LABEL" 2>/dev/null
        sleep 0.3
        launchctl bootstrap "gui/$UID_VAL" "$HOME/Library/LaunchAgents/$LABEL.plist" 2>/dev/null || return 1
      fi

      # Wait for port (up to 2s)
      local i=0
      while ! server_up && (( i < 20 )); do
        sleep 0.1
        ((i++))
      done
      server_up
    }

    case "''${1:-}" in
      # ── Server lifecycle management ──
      server)
        case "''${2:-status}" in
          start)
            if server_up; then
              echo "already running"
            elif ensure_server; then
              echo "started"
            else
              echo "failed"
            fi
            ;;
          stop)    launchctl bootout "gui/$UID_VAL/$LABEL" 2>/dev/null && echo "stopped" || echo "not running" ;;
          restart) launchctl bootout "gui/$UID_VAL/$LABEL" 2>/dev/null; sleep 0.5; launchctl bootstrap "gui/$UID_VAL" "$HOME/Library/LaunchAgents/$LABEL.plist" 2>/dev/null && echo "restarted" || echo "failed" ;;
          status)
            if server_up; then
              PID=$(launchctl list "$LABEL" 2>/dev/null | awk '/PID/ {print $NF}')
              echo "running (pid $PID, port ${toString serverPort})"
            elif launchctl list "$LABEL" &>/dev/null; then
              echo "stopped (stale — 'opencode server start' will auto-recover)"
            else
              echo "stopped"
            fi
            ;;
          log)     tail -f /tmp/opencode-server.log ;;
          debug)
            "$0" server stop
            while server_up; do sleep 0.1; done
            trap '"$0" server start' EXIT
            echo "Starting debug server on port ${toString serverPort} (Ctrl-C to stop)..."
            echo "Logs: /tmp/opencode-debug.log"
            "$REAL" serve --port "${toString serverPort}" --log-level DEBUG --print-logs 2>&1 | tee /tmp/opencode-debug.log
            ;;
          *)       echo "usage: opencode server [start|stop|restart|status|log|debug]" ;;
        esac
        exit
        ;;

      # ── Subcommands that always pass through unchanged ──
      completion|acp|mcp|debug|providers|auth|agent|upgrade|uninstall \
      |serve|web|models|stats|export|import|github|pr|session|db \
      |workspace-serve|attach)
        exec "$REAL" "$@"
        ;;

      # ── One-shot run: inject --attach when server is up ──
      run)
        if ensure_server && [[ " $* " != *" --attach "* ]]; then
          shift
          exec "$REAL" run --attach "$URL" "$@"
        fi
        exec "$REAL" "$@"
        ;;

      # ── TUI mode (no subcommand) ──
      *)
        if ensure_server; then
          if [[ -n "''${1:-}" && "''${1:0:1}" != "-" && -d "$1" ]]; then
            DIR="$1"
            shift
          else
            DIR="$(pwd)"
          fi
          exec "$REAL" attach "$URL" --dir "$DIR" "$@"
        fi
        exec "$REAL" "$@"
        ;;
    esac
  '';
in
{
  system = {
    launchd.user.agents.opencode-server = {
      serviceConfig = {
        Label = "com.opencode.server";
        ProgramArguments = [
          "${opencode-unwrapped}/bin/opencode"
          "serve"
          "--port"
          "${toString serverPort}"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/opencode-server.log";
        StandardErrorPath = "/tmp/opencode-server.log";
      };
    };
  };

  home = {
    programs.opencode.package = opencode-wrapper;
  };
}
