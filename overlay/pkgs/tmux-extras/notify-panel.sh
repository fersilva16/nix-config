#!/usr/bin/env bash

# tmux-notify-panel: Floating popup that displays notifications
# Renders a scrollable list with keybindings to dismiss or jump to source.
#
# Keybindings:
#   j/k or arrows  Navigate up/down
#   Enter          Jump to the tmux window that triggered the notification
#   d              Dismiss selected notification
#   D              Dismiss all notifications
#   q/Escape       Close panel

set -eu

NOTIFY_FILE="${TMUX_NOTIFY_FILE:-/tmp/tmux-notifications.json}"

# Terminal styling
BOLD=$(tput bold)
DIM=$(tput dim)
RESET=$(tput sgr0)
CYAN=$(tput setaf 6)
YELLOW=$(tput setaf 3)
MAGENTA=$(tput setaf 5)
REVERSE=$(tput rev)

# State
SELECTED=0
SCROLL_OFFSET=0

get_notifications() {
  if [[ ! -f "$NOTIFY_FILE" ]]; then
    echo '[]'
    return
  fi
  # Return newest first
  jq 'sort_by(.timestamp) | reverse' "$NOTIFY_FILE" 2>/dev/null || echo '[]'
}

render() {
  local notifications="$1"
  local count
  count=$(echo "$notifications" | jq 'length')
  local term_height
  term_height=$(tput lines)
  local max_items=$((term_height - 5)) # Reserve lines for header/footer

  clear

  # Header
  echo "${BOLD}${MAGENTA}  Notifications${RESET}  ${DIM}(${count})${RESET}"
  echo "${DIM}$(printf '%.0s─' $(seq 1 56))${RESET}"

  if [[ "$count" -eq 0 ]]; then
    echo ""
    echo "  ${DIM}No notifications${RESET}"
    echo ""
    echo "${DIM}$(printf '%.0s─' $(seq 1 56))${RESET}"
    echo "  ${DIM}press q to close${RESET}"
    return
  fi

  # Ensure selected is within bounds
  if [[ $SELECTED -ge $count ]]; then
    SELECTED=$((count - 1))
  fi
  if [[ $SELECTED -lt 0 ]]; then
    SELECTED=0
  fi

  # Adjust scroll offset to keep selected visible
  if [[ $SELECTED -lt $SCROLL_OFFSET ]]; then
    SCROLL_OFFSET=$SELECTED
  fi
  if [[ $SELECTED -ge $((SCROLL_OFFSET + max_items)) ]]; then
    SCROLL_OFFSET=$((SELECTED - max_items + 1))
  fi

  local i
  for ((i = SCROLL_OFFSET; i < count && i < SCROLL_OFFSET + max_items; i++)); do
    local entry
    entry=$(echo "$notifications" | jq -r ".[$i]")
    local session
    session=$(echo "$entry" | jq -r '.session')
    local message
    message=$(echo "$entry" | jq -r '.message')
    local timestamp
    timestamp=$(echo "$entry" | jq -r '.timestamp')

    # Format timestamp to just time
    local time_display
    time_display=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" "+%H:%M" 2>/dev/null || echo "${timestamp:11:5}")

    # Truncate message to fit
    local max_msg_len=32
    if [[ ${#message} -gt $max_msg_len ]]; then
      message="${message:0:$max_msg_len}…"
    fi

    local prefix=" "
    local style=""

    if [[ $i -eq $SELECTED ]]; then
      style="${REVERSE}"
      prefix="▸"
    fi

    printf " %s ${CYAN}●${RESET} ${style}${YELLOW}%-8s${RESET}${style} %s ${DIM}%s${RESET}\n" \
      "$prefix" "$session" "$message" "$time_display"
  done

  # Scroll indicator
  if [[ $count -gt $max_items ]]; then
    local visible_end=$((SCROLL_OFFSET + max_items))
    if [[ $visible_end -gt $count ]]; then
      visible_end=$count
    fi
    echo "${DIM}  [$((SCROLL_OFFSET + 1))-${visible_end} of ${count}]${RESET}"
  fi

  echo "${DIM}$(printf '%.0s─' $(seq 1 56))${RESET}"
  echo "  ${DIM}j/k${RESET} navigate  ${DIM}Enter${RESET} goto  ${DIM}d${RESET} dismiss  ${DIM}D${RESET} all  ${DIM}q${RESET} close"
}

dismiss_selected() {
  local notifications="$1"
  local count
  count=$(echo "$notifications" | jq 'length')

  if [[ $count -eq 0 ]]; then
    return
  fi

  local id
  id=$(echo "$notifications" | jq -r ".[$SELECTED].id")

  if [[ -n "$id" && "$id" != "null" ]]; then
    tmux-notify dismiss "$id"
  fi
}

dismiss_all() {
  tmux-notify dismiss all
  SELECTED=0
  SCROLL_OFFSET=0
}

# Jump to the tmux window that triggered the selected notification
goto_selected() {
  local notifications="$1"
  local count
  count=$(echo "$notifications" | jq 'length')

  if [[ $count -eq 0 ]]; then
    return
  fi

  local target
  target=$(echo "$notifications" | jq -r ".[$SELECTED].target // empty")

  if [[ -n "$target" ]]; then
    # Dismiss the notification and switch to the target window
    dismiss_selected "$notifications"
    # select-window works across sessions (target is "session:window")
    tmux select-window -t "$target" 2>/dev/null || true
    tmux switch-client -t "$target" 2>/dev/null || true
    exit 0
  fi
}

# Hide cursor
tput civis 2>/dev/null || true
trap 'tput cnorm 2>/dev/null || true' EXIT

# Main loop
while true; do
  notifications=$(get_notifications)
  render "$notifications"

  # Read a single key
  IFS= read -rsn1 key

  case "$key" in
    j)
      SELECTED=$((SELECTED + 1))
      ;;
    k)
      SELECTED=$((SELECTED - 1))
      ;;
    '')
      goto_selected "$notifications"
      ;;
    d)
      dismiss_selected "$notifications"
      ;;
    D)
      dismiss_all
      ;;
    q)
      exit 0
      ;;
    $'\e')
      # Handle escape sequences (arrow keys send \e[A, \e[B, etc.)
      read -rsn1 -t 0.1 next_key || true
      if [[ "${next_key:-}" == "[" ]]; then
        read -rsn1 -t 0.1 arrow_key || true
        case "${arrow_key:-}" in
          A) SELECTED=$((SELECTED - 1)) ;;
          B) SELECTED=$((SELECTED + 1)) ;;
        esac
      else
        # Plain escape key - close panel
        exit 0
      fi
      ;;
  esac
done
