#!/usr/bin/env bash

# tmux-notify-widget: Status bar widget showing notification count
# Displays a bell icon with count when there are pending notifications.
# Shows nothing when empty (clean status bar).

NOTIFY_FILE="${TMUX_NOTIFY_FILE:-/tmp/tmux-notifications.json}"

# Flexoki light theme colors
BG="#f2f0e5"
FG="#100f0f"
ORANGE="#da702c"

RESET="#[fg=${FG},bg=${BG},nobold,noitalics,nounderscore,nodim]"

if [[ ! -f "$NOTIFY_FILE" ]]; then
  exit 0
fi

COUNT=$(jq 'length' "$NOTIFY_FILE" 2>/dev/null || echo 0)

if [[ "$COUNT" -gt 0 ]]; then
  echo "#[fg=${ORANGE},bg=${BG},bold] 󰂞 ${COUNT} ${RESET}"
fi
