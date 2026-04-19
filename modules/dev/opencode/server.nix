{
  pkgs,
  lib,
  opencode-unwrapped,
  serverPort,
}:
let
  serverUrl = "http://127.0.0.1:${toString serverPort}";

  # Launchd agents inherit a minimal PATH (/usr/bin:/bin:/usr/sbin:/sbin),
  # which breaks opencode plugins that shell out to user-installed tools.
  # In particular, @simonwjackson/opencode-direnv invokes `direnv export json`
  # via Bun's `$` shell helper, and direnv itself needs `nix` on PATH to
  # evaluate `use flake` .envrc files.  We mirror a login shell's PATH so
  # plugins running inside the server can find direnv, nix, and friends.
  serverLauncher = pkgs.writeShellScript "opencode-server-launcher" ''
    export PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    exec ${opencode-unwrapped}/bin/opencode serve --port ${toString serverPort}
  '';

  # Wrapper that provides server lifecycle commands and optionally
  # auto-attaches TUI clients to the shared server.
  mkWrapper =
    autoAttach:
    pkgs.writeShellScriptBin "opencode" ''
      REAL="${opencode-unwrapped}/bin/opencode"
      URL="${serverUrl}"
      AUTO_ATTACH=${if autoAttach then "1" else "0"}

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

      # Attach TUI to the running server, mapping the tmux pane to its
      # opencode session.
      #
      # State is stored as tmux pane user options (@oc-sid, @oc-dir) —
      # auto-cleaned when panes die, survives detach. Plugins run
      # server-side without TMUX_PANE, so the wrapper (which runs
      # client-side in the tmux pane) owns the mapping.
      #
      # Live session tracking after launch is handled out-of-band by the
      # `pane-title-changed` tmux hook in `opencode-manager`, which runs
      # `tmux-oc-sync-sid` to re-resolve `@oc-sid` from the DB whenever
      # the TUI updates the pane title to `OC | <session.title>`. This
      # avoids holding a per-pane SSE subscriber against the server
      # (which previously overflowed opencode's EventEmitter listener
      # cap and wedged the HTTP layer).
      #
      # Usage: attach_to_server <DIR> [opencode args...]
      attach_to_server() {
        local DIR="$1"
        shift

        _PANE="''${TMUX_PANE:-}"

        if [[ -n "$_PANE" ]]; then
          _DB="$HOME/.local/share/opencode/opencode-local.db"

          # Parse --session and --fork from args
          _oc_sid="" _oc_fork=0 _prev=""
          for _arg in "$@"; do
            case "$_prev" in --session|-s) _oc_sid="$_arg" ;; esac
            [[ "$_arg" == "--fork" ]] && _oc_fork=1
            _prev="$_arg"
          done

          tmux set-option -p -t "$_PANE" @oc-dir "$DIR"

          # ── Pre-launch session resolution ──
          # Best-effort: set @oc-sid + @oc-status=active when we can
          # resolve a session before exec. For fork or first-launch-in-dir
          # we leave both unset and let the pane-title hook resolve
          # post-launch once the TUI sets the title.
          if [[ -n "$_oc_sid" && "$_oc_fork" -eq 0 ]]; then
            # Explicit --session, no fork: known immediately
            tmux set-option -p -t "$_PANE" @oc-sid "$_oc_sid"
            tmux set-option -p -t "$_PANE" @oc-status active
          elif [[ "$_oc_fork" -eq 0 ]]; then
            # Default/continue: resolve from DB before launch
            _sid=$(sqlite3 "$_DB" \
              "SELECT id FROM session WHERE directory='$DIR'
               ORDER BY time_updated DESC LIMIT 1" 2>/dev/null || true)
            if [[ -n "$_sid" ]]; then
              tmux set-option -p -t "$_PANE" @oc-sid "$_sid"
              tmux set-option -p -t "$_PANE" @oc-status active
            fi
          fi
        fi

        exec "$REAL" attach "$URL" --dir "$DIR" "$@"
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
            restart)
              launchctl bootout "gui/$UID_VAL/$LABEL" 2>/dev/null
              # Wait for server to fully stop before re-bootstrapping (up to 5s)
              i=0
              while server_up && (( i < 50 )); do
                sleep 0.1
                ((i++))
              done
              if launchctl bootstrap "gui/$UID_VAL" "$HOME/Library/LaunchAgents/$LABEL.plist" 2>/dev/null; then
                echo "restarted"
              else
                echo "failed"
              fi
              ;;
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
            connect)
              if ! ensure_server; then
                echo "server not running — start with: opencode server start"
                exit 1
              fi
              shift 2
              if [[ -n "''${1:-}" && "''${1:0:1}" != "-" && -d "$1" ]]; then
                DIR="$1"; shift
              else
                DIR="$(pwd)"
              fi
              attach_to_server "$DIR" "$@"
              ;;
            *)       echo "usage: opencode server [start|stop|restart|status|log|debug|connect]" ;;
          esac
          exit
          ;;

        # ── Solo: bypass all wrapper logic, exec raw opencode ──
        # Escape hatch for when the shared server is broken or you
        # explicitly want a session not tied to it.
        # Usage: opencode solo [args...]
        solo)
          shift
          exec "$REAL" "$@"
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
          if (( AUTO_ATTACH )) && ensure_server; then
            if [[ -n "''${1:-}" && "''${1:0:1}" != "-" && -d "$1" ]]; then
              DIR="$1"
              shift
            else
              DIR="$(pwd)"
            fi
            attach_to_server "$DIR" "$@"
          fi
          exec "$REAL" "$@"
          ;;
      esac
    '';
in
{
  extraOptions = {
    autoAttach = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Auto-attach TUI to the shared server. When false, `opencode` runs standalone and `opencode server connect` attaches manually.";
    };
  };

  system = {
    launchd.user.agents.opencode-server = {
      serviceConfig = {
        Label = "com.opencode.server";
        ProgramArguments = [ "${serverLauncher}" ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/opencode-server.log";
        StandardErrorPath = "/tmp/opencode-server.log";
      };
    };
  };

  home =
    { cfg, ... }:
    {
      programs.opencode.package = mkWrapper cfg.autoAttach;
    };
}
