{
  username,
  pkgs,
  inputs,
  system,
  ...
}:
let
  jsonFormat = pkgs.formats.json { };
  inherit (pkgs)
    tmux-extras
    figma-developer-mcp
    agentation-mcp
    ;

  serverPort = 4096;
  serverUrl = "http://127.0.0.1:${toString serverPort}";

  # Real opencode binary with patches applied
  opencode-unwrapped = inputs.opencode.packages.${system}.default.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./patches/cursor-style-and-blink.patch ];
  });

  # Wrapper that auto-attaches TUI clients and `run` commands to the
  # shared server managed by the launchd agent below.  Falls back to
  # normal (standalone) behaviour when the server is unreachable.
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

    case "''${1:-}" in
      # ── Server lifecycle management ──
      server)
        case "''${2:-status}" in
          start)   launchctl kickstart "gui/$UID_VAL/$LABEL" 2>/dev/null && echo "started" || echo "already running" ;;
          stop)    launchctl kill SIGTERM "gui/$UID_VAL/$LABEL" 2>/dev/null && echo "stopped" || echo "not running" ;;
          restart) launchctl kickstart -k "gui/$UID_VAL/$LABEL" 2>/dev/null && echo "restarted" || echo "failed" ;;
          status)
            if server_up; then
              PID=$(launchctl list "$LABEL" 2>/dev/null | awk '/PID/ {print $NF}')
              echo "running (pid $PID, port ${toString serverPort})"
            else
              echo "stopped"
            fi
            ;;
          log)     tail -f /tmp/opencode-server.log ;;
          *)       echo "usage: opencode server [start|stop|restart|status|log]" ;;
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
        if server_up && [[ " $* " != *" --attach "* ]]; then
          shift
          exec "$REAL" run --attach "$URL" "$@"
        fi
        exec "$REAL" "$@"
        ;;

      # ── TUI mode (no subcommand) ──
      *)
        if server_up; then
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
  # ── Shared headless server (launchd user agent) ──
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

  home-manager.users.${username} = {
    programs.opencode = {
      enable = true;
      package = opencode-wrapper;
      settings = {
        theme = "flexoki";
        plugin = [
          "@ex-machina/opencode-anthropic-auth@0.2.1"
          "@simonwjackson/opencode-direnv@2025.1211.9"
          "@mohak34/opencode-notifier@0.1.36"
          "oh-my-opencode@3.14.0"
          "@rama_nigg/open-cursor@2.3.20"
        ];
        provider = {
          cursor-acp = {
            name = "Cursor ACP";
            npm = "@ai-sdk/openai-compatible";
            options = {
              baseURL = "http://127.0.0.1:32124/v1";
            };
            models = {
              "cursor-acp/auto" = {
                name = "Auto";
              };
              "cursor-acp/composer-1.5" = {
                name = "Composer 1.5";
              };
              "cursor-acp/composer-1" = {
                name = "Composer 1";
              };
            };
          };
        };
        command = {
          lin = {
            template = "Here is the Linear issue for this branch:\n\n!`lin`\n\nSummarize the issue and ask what I want to work on.";
            description = "Load Linear issue context";
          };
        };
        permission = {
          external_directory = "allow";
          read = {
            "*" = "allow";
            "*.env" = "deny";
            "*.env.*" = "allow";
          };
          edit = {
            "*" = "allow";
            "*.env" = "deny";
            "*.env.*" = "allow";
          };
        };
        agent = {
          title = {
            model = "opencode/minimax-m2.5-free";
          };
        };
        mcp = {
          framelink = {
            enabled = false;
            type = "local";
            command = [
              "${figma-developer-mcp}/bin/figma-developer-mcp"
              "--stdio"
              "--env"
              "/Users/${username}/.config/figma/.env"
            ];
          };
          agentation = {
            enabled = false;
            type = "local";
            command = [
              "${agentation-mcp}/bin/agentation-mcp"
              "server"
            ];
          };
        };
      };
    };

    xdg.configFile = {
      "opencode/tui.json".source = jsonFormat.generate "tui.json" {
        cursor_style = "line";
        cursor_blink = true;
      };

      "opencode/oh-my-opencode.json".source = jsonFormat.generate "oh-my-opencode.json" {
        "$schema" =
          "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/oh-my-opencode.schema.json";
        agents = {
          build = {
            model = "anthropic/claude-opus-4-6";
          };
          sisyphus = {
            model = "anthropic/claude-opus-4-6";
            variant = "max";
          };
          oracle = {
            model = "anthropic/claude-opus-4-6";
            variant = "max";
          };
          explore = {
            model = "anthropic/claude-haiku-4-5";
          };
          multimodal-looker = {
            model = "opencode/glm-4.7-free";
          };
          prometheus = {
            model = "anthropic/claude-opus-4-6";
            variant = "max";
          };
          metis = {
            model = "anthropic/claude-opus-4-6";
            variant = "max";
          };
          momus = {
            model = "anthropic/claude-opus-4-6";
            variant = "max";
          };
          atlas = {
            model = "anthropic/claude-sonnet-4-5";
          };
          sisyphus-junior = {
            model = "anthropic/claude-sonnet-4-6";
          };
        };
        categories = {
          visual-engineering = {
            model = "anthropic/claude-opus-4-6";
            variant = "max";
          };
          ultrabrain = {
            model = "anthropic/claude-opus-4-6";
            variant = "max";
          };
          quick = {
            model = "anthropic/claude-haiku-4-5";
          };
          unspecified-low = {
            model = "anthropic/claude-sonnet-4-5";
          };
          unspecified-high = {
            model = "anthropic/claude-opus-4-6";
            variant = "max";
          };
          writing = {
            model = "anthropic/claude-sonnet-4-5";
          };
        };
      };

      "opencode/opencode-notifier.json".source = jsonFormat.generate "opencode-notifier.json" {
        sound = true;
        notification = false;
        suppressWhenFocused = false;
        command = {
          enabled = true;
          path = "${tmux-extras}/bin/tmux-notify";
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
}
