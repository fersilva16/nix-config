#!/usr/bin/env bash

# tmux-battery-widget: Status bar widget showing battery percentage and state.
# Only shown when remote access mode is active (to keep status bar clean normally).
# Uses pmset to read battery info on macOS.

STATE_FILE="/tmp/tmux-remote-state"

# Flexoki light theme colors
BG="#f2f0e5"
FG="#100f0f"
GREEN="#879a39"
YELLOW="#d0a215"
RED="#d14d41"
ORANGE="#da702c"

RESET="#[fg=${FG},bg=${BG},nobold,noitalics,nounderscore,nodim]"

# Only show battery when remote mode is active
if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# Read battery info from pmset
BATTERY_INFO=$(pmset -g batt 2>/dev/null)

if [[ -z "$BATTERY_INFO" ]]; then
  exit 0
fi

# Extract percentage (e.g., "85%")
PERCENT=$(echo "$BATTERY_INFO" | grep -oE '[0-9]+%' | head -1 | tr -d '%')

if [[ -z "$PERCENT" ]]; then
  exit 0
fi

# Determine charging state
CHARGING=""
if echo "$BATTERY_INFO" | grep -q "AC Power"; then
  CHARGING="󰂄"
elif echo "$BATTERY_INFO" | grep -q "charged"; then
  CHARGING="󰂄"
fi

# Pick icon and color based on percentage
if [[ "$PERCENT" -ge 80 ]]; then
  ICON="󰁹"
  COLOR="$GREEN"
elif [[ "$PERCENT" -ge 60 ]]; then
  ICON="󰂀"
  COLOR="$GREEN"
elif [[ "$PERCENT" -ge 40 ]]; then
  ICON="󰁾"
  COLOR="$YELLOW"
elif [[ "$PERCENT" -ge 20 ]]; then
  ICON="󰁻"
  COLOR="$ORANGE"
else
  ICON="󰁺"
  COLOR="$RED"
fi

# Use charging icon if plugged in
if [[ -n "$CHARGING" ]]; then
  ICON="$CHARGING"
fi

echo "#[fg=${COLOR},bg=${BG},bold] ${ICON} ${PERCENT}%${RESET} "
