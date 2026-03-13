#!/usr/bin/env bash

# tmux-remote-widget: Status bar widget showing remote access state.
# Displays an SSH icon when remote access is active.
# Shows nothing when inactive (clean status bar).

STATE_FILE="/tmp/tmux-remote-state"

# Flexoki light theme colors
BG="#f2f0e5"
FG="#100f0f"
RED="#d14d41"

RESET="#[fg=${FG},bg=${BG},nobold,noitalics,nounderscore,nodim]"

if [[ -f "$STATE_FILE" ]]; then
  echo "#[fg=${RED},bg=${BG},bold] 󰣀 SSH ${RESET}"
fi
