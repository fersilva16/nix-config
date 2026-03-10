#!/usr/bin/env bash
# tmux-attach: Attach to the most recent tmux session, or create one.

SESSION=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | head -1)

if [ -z "$SESSION" ]; then
  exec tmux new-session -s main
fi

exec tmux attach-session -t "$SESSION"
