# shellcheck shell=sh
# Sourced from ~/.profile (see agent-path.nix). Login shells in agents/* tmux
# sessions get the agent PATH, like omo's own tool calls: those sessions take
# their environment from the tmux server, not from the agent that made them.
if [ -n "${TMUX_PANE:-}" ]; then
  case "$(tmux display-message -p -t "$TMUX_PANE" '#S' 2>/dev/null)" in
    agents/*) PATH="$HOME/.agents/bin:$PATH" ;;
  esac
fi
