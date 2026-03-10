#!/usr/bin/env bash
# tmux-group: Create a grouped session from the current session.
# Opens in a new Ghostty window with independent window selection.

SESSION=$(tmux display-message -p "#{session_name}")

# Don't group an already grouped session — use its parent instead
if [[ "$SESSION" =~ _g[0-9]+$ ]]; then
  SESSION="${SESSION%_g[0-9]*}"
fi

# Find next available group ID
id=1
while tmux has-session -t "${SESSION}_g${id}" 2>/dev/null; do
  id=$((id + 1))
done

GROUP_SESSION="${SESSION}_g${id}"

# Open a new Ghostty window that creates the grouped session.
# destroy-unattached ensures cleanup when the window closes.
open -na Ghostty --args -e tmux new-session -t "$SESSION" -s "$GROUP_SESSION" \; \
  set-option destroy-unattached on
