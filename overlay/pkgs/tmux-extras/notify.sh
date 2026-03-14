#!/usr/bin/env bash

# tmux-notify: Notification state manager for tmux
# Stores notifications in a JSON file and provides subcommands to manage them.
#
# Usage:
#   tmux-notify add [--event <type>] <message>   Add a notification
#   tmux-notify dismiss <id|all>                 Remove notification(s)
#   tmux-notify list                             Output all notifications as JSON
#   tmux-notify count                            Output notification count
#   tmux-notify open                             Open the notification panel popup
#
# Events:
#   Only "complete", "permission", "error", "question" events are recorded. Subagent and user_cancelled events are ignored.
#
# Environment:
#   TMUX_NOTIFY_FILE   Override notification file path (default: /tmp/tmux-notifications.json)

set -eu

NOTIFY_FILE="${TMUX_NOTIFY_FILE:-/tmp/tmux-notifications.json}"
LOCK_FILE="${NOTIFY_FILE}.lock"

# Ensure the notification file exists
init_file() {
  if [[ ! -f "$NOTIFY_FILE" ]]; then
    echo '[]' > "$NOTIFY_FILE"
  fi
}

# Simple file locking using mkdir (atomic on all platforms)
lock() {
  local attempts=0
  while ! mkdir "$LOCK_FILE" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [[ $attempts -gt 50 ]]; then
      # Stale lock, remove and retry
      rm -rf "$LOCK_FILE"
    fi
    sleep 0.01
  done
}

unlock() {
  rm -rf "$LOCK_FILE"
}

# Add a notification
cmd_add() {
  local event=""
  local message=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --event)
        event="${2:-}"
        shift 2
        ;;
      *)
        message="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$message" ]]; then
    echo "Usage: tmux-notify add [--event <type>] <message>" >&2
    exit 1
  fi

  # Filter: only allow task completion events through
  # Known events: complete, subagent_complete, error, permission, question, user_cancelled
  if [[ -n "$event" ]]; then
    case "$event" in
      complete) ;; # allow
      permission) ;; # allow
      error) ;; # allow
      question) ;; # allow
      *)
        # Silently ignore subagent and user_cancelled events
        exit 0
        ;;
    esac
  fi

  local id timestamp session window target
  id="$(printf '%s%s' "$(date +%s)" "$$" | shasum | head -c 8)"
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Try to detect the session and window from tmux
  # Use $TMUX_PANE with -t flag for reliable detection from child processes
  session="${TMUX_NOTIFY_SESSION:-}"
  window=""
  target=""
  if command -v tmux &>/dev/null; then
    local pane_target="${TMUX_PANE:-}"

    # Skip notification if the pane is in the currently active window
    # of an attached session (i.e., the user is actually looking at it)
    if [[ -n "$pane_target" ]]; then
      local pane_active session_attached
      pane_active="$(tmux display-message -p -t "$pane_target" '#{window_active}' 2>/dev/null || true)"
      session_attached="$(tmux display-message -p -t "$pane_target" '#{session_attached}' 2>/dev/null || true)"
      if [[ "$pane_active" == "1" && "${session_attached:-0}" -gt 0 ]]; then
        exit 0
      fi
    fi

    if [[ -n "$pane_target" ]]; then
      if [[ -z "$session" ]]; then
        session="$(tmux display-message -p -t "$pane_target" '#S' 2>/dev/null || true)"
      fi
      window="$(tmux display-message -p -t "$pane_target" '#I' 2>/dev/null || true)"
    else
      if [[ -z "$session" ]]; then
        session="$(tmux display-message -p '#S' 2>/dev/null || true)"
      fi
      window="$(tmux display-message -p '#I' 2>/dev/null || true)"
    fi
    if [[ -n "$session" && -n "$window" ]]; then
      target="${session}:${window}"
    fi
  fi
  session="${session:-opencode}"

  init_file
  lock

  local entry
  entry=$(jq -n \
    --arg id "$id" \
    --arg ts "$timestamp" \
    --arg sess "$session" \
    --arg msg "$message" \
    --arg tgt "$target" \
    '{id: $id, timestamp: $ts, session: $sess, message: $msg, target: $tgt}')

  jq --argjson entry "$entry" '. += [$entry]' "$NOTIFY_FILE" > "${NOTIFY_FILE}.tmp" \
    && mv "${NOTIFY_FILE}.tmp" "$NOTIFY_FILE"

  unlock

  # Flash a styled message in the tmux status bar and refresh the widget
  if command -v tmux &>/dev/null; then
    tmux refresh-client -S 2>/dev/null || true
    # Temporarily set a clean message style matching the flexoki light theme
    tmux set -g message-style "fg=#da702c,bg=#f2f0e5" 2>/dev/null || true
    tmux display-message -d 5000 "󰂞  ${session}: ${message}" 2>/dev/null || true
  fi

  # Send terminal bell when remote mode is active.
  # Termius (and most iOS SSH clients) surface BEL as an iOS notification
  # when the app is backgrounded, providing a vibration/alert on the phone.
  if [[ -f "/tmp/tmux-remote-state" ]]; then
    # Send BEL to all tmux clients so the SSH session receives it
    local pane_target="${TMUX_PANE:-}"
    if [[ -n "$pane_target" ]]; then
      tmux send-keys -t "$pane_target" "" 2>/dev/null || true
    else
      printf '\a'
    fi
  fi
}

# Dismiss (remove) one or all notifications
cmd_dismiss() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    echo "Usage: tmux-notify dismiss <id|all>" >&2
    exit 1
  fi

  init_file
  lock

  if [[ "$target" == "all" ]]; then
    echo '[]' > "$NOTIFY_FILE"
  else
    jq --arg id "$target" '[.[] | select(.id != $id)]' "$NOTIFY_FILE" > "${NOTIFY_FILE}.tmp" \
      && mv "${NOTIFY_FILE}.tmp" "$NOTIFY_FILE"
  fi

  unlock
}

# List all notifications as JSON
cmd_list() {
  init_file
  cat "$NOTIFY_FILE"
}

# Count notifications
cmd_count() {
  init_file
  jq 'length' "$NOTIFY_FILE"
}

# Open the notification panel popup
cmd_open() {
  if ! command -v tmux &>/dev/null; then
    echo "tmux is not available" >&2
    exit 1
  fi

  local panel_script
  panel_script="$(command -v tmux-notify-panel)"
  tmux display-popup -w 60 -h 20 -E "$panel_script"
}

# Jump to the most recent notification's window and dismiss it
cmd_goto() {
  init_file

  local count
  count=$(jq 'length' "$NOTIFY_FILE")
  if [[ "$count" -eq 0 ]]; then
    tmux display-message "No notifications" 2>/dev/null || true
    return
  fi

  # Get the newest notification (last in the array)
  local target id
  target=$(jq -r '.[-1].target // empty' "$NOTIFY_FILE")
  id=$(jq -r '.[-1].id' "$NOTIFY_FILE")

  # Dismiss it
  if [[ -n "$id" && "$id" != "null" ]]; then
    cmd_dismiss "$id"
  fi

  # Switch to the target window and refresh status bar
  if command -v tmux &>/dev/null; then
    tmux refresh-client -S 2>/dev/null || true
    if [[ -n "$target" ]]; then
      tmux select-window -t "$target" 2>/dev/null || true
      tmux switch-client -t "$target" 2>/dev/null || true
    fi
  fi
}

# Main dispatch
case "${1:-}" in
  add)     shift; cmd_add "$@" ;;
  dismiss) shift; cmd_dismiss "$@" ;;
  goto)    cmd_goto ;;
  list)    cmd_list ;;
  count)   cmd_count ;;
  open)    cmd_open ;;
  *)
    echo "Usage: tmux-notify <add|dismiss|goto|list|count|open> [args...]" >&2
    exit 1
    ;;
esac
