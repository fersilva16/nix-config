#!/usr/bin/env bash

# tmux-notify-widget: Status bar widget showing generating opencode count and notification count.

NOTIFY_FILE="${TMUX_NOTIFY_FILE:-/tmp/tmux-notifications.json}"

BG="#f2f0e5"
FG="#100f0f"
ORANGE="#da702c"
GREEN="#879a39"

RESET="#[fg=${FG},bg=${BG},nobold,noitalics,nounderscore,nodim]"

ACTIVE=$(tmux-opencode-generating 2>/dev/null || echo '[]')
ACTIVE=$(echo "$ACTIVE" | jq 'length' 2>/dev/null || echo 0)

NOTIFS=0
if [[ -f "$NOTIFY_FILE" ]]; then
  NOTIFS=$(jq 'length' "$NOTIFY_FILE" 2>/dev/null || echo 0)
fi

OUTPUT=""

if [[ "$ACTIVE" -gt 0 ]]; then
  if [[ "${1:-}" == "--plain" ]]; then
    OUTPUT="G:${ACTIVE}"
  else
    OUTPUT="#[fg=${GREEN},bg=${BG},bold] ⏳ ${ACTIVE}${RESET}"
  fi
fi

if [[ "$NOTIFS" -gt 0 ]]; then
  if [[ "${1:-}" == "--plain" ]]; then
    OUTPUT="${OUTPUT} !${NOTIFS}"
  else
    OUTPUT="${OUTPUT}#[fg=${ORANGE},bg=${BG},bold] 󰂞 ${NOTIFS}${RESET}"
  fi
fi

echo "$OUTPUT"
