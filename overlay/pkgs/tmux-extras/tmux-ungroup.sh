#!/usr/bin/env bash
# tmux-ungroup: Leave and destroy the current grouped session.
# If not in a grouped session, does nothing.

SESSION=$(tmux display-message -p "#{session_name}")

if [[ ! "$SESSION" =~ _g[0-9]+$ ]]; then
  tmux display-message "Not in a grouped session"
  exit 0
fi

# Kill this grouped session — tmux will close the client (and Ghostty window)
tmux kill-session -t "$SESSION"
