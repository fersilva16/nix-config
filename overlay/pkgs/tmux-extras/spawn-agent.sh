#!/usr/bin/env bash

# tmux-spawn-agent: Spawn an opencode agent in a dedicated "agents" window
#
# Usage: tmux-spawn-agent <pane_path> <prompt...>
#
# Creates a tiled "agents" window for running multiple opencode instances
# in parallel. First call creates the window; subsequent calls add panes.
# Dead panes are preserved so output can be reviewed (close with prefix + x).

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

if ! tmux list-windows -t "$SESSION" -F '#W' | grep -q "^${AGENTS_WINDOW}$"; then
  tmux new-window -t "$SESSION" -n "$AGENTS_WINDOW" -c "$GIT_ROOT" "opencode run ${SAFE_PROMPT}"
  tmux set-option -w -t "$TARGET" remain-on-exit on
else
  tmux split-window -t "$TARGET" -c "$GIT_ROOT" "opencode run ${SAFE_PROMPT}"
  tmux select-layout -t "$TARGET" tiled
fi

tmux select-window -t "$TARGET"
