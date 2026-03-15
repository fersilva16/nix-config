#!/usr/bin/env bash

# tmux-status-right: Unified status bar right side.
# When remote mode is active, shows a minimal bar (SSH + battery).
# When inactive, shows the full bar (notifications + path + git).

STATE_FILE="/tmp/tmux-remote-state"
PANE_PATH="${1:-}"

# Flexoki light theme colors
BG="#f2f0e5"
FG="#100f0f"
RED="#d14d41"
GREEN="#879a39"
YELLOW="#d0a215"
ORANGE="#da702c"

RESET="#[fg=${FG},bg=${BG},nobold,noitalics,nounderscore,nodim]"

# --- Battery widget (inline, only in remote mode) ---
battery_widget() {
  local info percent icon color charging=""
  info=$(pmset -g batt 2>/dev/null)
  [[ -z "$info" ]] && return

  percent=$(echo "$info" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
  [[ -z "$percent" ]] && return

  if echo "$info" | grep -q "AC Power"; then
    charging="󰂄"
  elif echo "$info" | grep -q "charged"; then
    charging="󰂄"
  fi

  if [[ "$percent" -ge 80 ]]; then
    icon="󰁹"; color="$GREEN"
  elif [[ "$percent" -ge 60 ]]; then
    icon="󰂀"; color="$GREEN"
  elif [[ "$percent" -ge 40 ]]; then
    icon="󰁾"; color="$YELLOW"
  elif [[ "$percent" -ge 20 ]]; then
    icon="󰁻"; color="$ORANGE"
  else
    icon="󰁺"; color="$RED"
  fi

  [[ -n "$charging" ]] && icon="$charging"

  echo "#[fg=${color},bg=${BG},bold] ${icon} ${percent}%${RESET}"
}

if [[ -f "$STATE_FILE" ]]; then
  # ---- Remote mode: minimal bar ----
  # SSH indicator + battery + time
  SSH="#[fg=${RED},bg=${BG},bold] 󰣀 SSH${RESET}"
  BATT=$(battery_widget)

  echo "${SSH}${BATT}"
else
  # ---- Normal mode: full bar ----
  # Notifications + path + git + date + time
  # These call the existing widget scripts
  SELF_DIR="$(dirname "$0")"

  NOTIFY=$("${SELF_DIR}/tmux-notify-widget")
  PATH_W=$("${SELF_DIR}/tmux-path-widget" "$PANE_PATH")
  GIT=$("${SELF_DIR}/tmux-git-status" "$PANE_PATH")

  echo "${NOTIFY}${PATH_W}${GIT}"
fi
