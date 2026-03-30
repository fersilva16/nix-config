#!/usr/bin/env bash

# tmux-notify: Notification state manager for tmux
# Stores notifications in a JSON file and provides subcommands to manage them.
#
# Usage:
#   tmux-notify add [--event <type>] <message>   Add a notification
#   tmux-notify dismiss <id|all>                 Remove notification(s)
#   tmux-notify dismiss-session <name>           Remove all notifications for a session
#   tmux-notify auto-dismiss                     Dismiss notifications for the current window

#   tmux-notify list                             Output all notifications as JSON
#   tmux-notify count                            Output notification count
#   tmux-notify open                             Open the notification panel popup
#
# Events:
#   Only "complete", "permission", "error", "question" events create notifications.
#   All other events are silently ignored.
#
# Environment:
#   TMUX_NOTIFY_FILE   Override notification file path (default: /tmp/tmux-notifications.json)

set -eu

NOTIFY_FILE="${TMUX_NOTIFY_FILE:-/tmp/tmux-notifications.json}"
LOCK_FILE="${NOTIFY_FILE}.lock"
init_file() {
  if [[ ! -f "$NOTIFY_FILE" ]]; then
    echo '[]' > "$NOTIFY_FILE"
  fi
}

lock() {
  local attempts=0
  while ! mkdir "$LOCK_FILE" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [[ $attempts -gt 50 ]]; then
      rm -rf "$LOCK_FILE"
    fi
    sleep 0.01
  done
}

unlock() {
  rm -rf "$LOCK_FILE"
}

cmd_add() {
  local event=""
  local message=""

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

  if [[ -n "$event" ]]; then
    case "$event" in
      complete|permission|error|question) ;;
      *) exit 0 ;;
    esac
  fi

  local id timestamp session window target
  id="$(printf '%s%s' "$(date +%s)" "$$" | shasum | head -c 8)"
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  session="${TMUX_NOTIFY_SESSION:-}"
  window=""
  target=""
  local pane_active="" session_attached=""

  if command -v tmux &>/dev/null; then
    local pane_target="${TMUX_PANE:-}"

    if [[ -n "$pane_target" ]]; then
      if [[ -z "$session" ]]; then
        session="$(tmux display-message -p -t "$pane_target" '#S' 2>/dev/null || true)"
      fi
      window="$(tmux display-message -p -t "$pane_target" '#I' 2>/dev/null || true)"
      pane_active="$(tmux display-message -p -t "$pane_target" '#{window_active}' 2>/dev/null || true)"
      session_attached="$(tmux display-message -p -t "$pane_target" '#{session_attached}' 2>/dev/null || true)"
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

  if [[ "$pane_active" == "1" && "${session_attached:-0}" -gt 0 ]]; then
    exit 0
  fi

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

  if command -v tmux &>/dev/null; then
    tmux refresh-client -S 2>/dev/null || true
    tmux set -g message-style "fg=#da702c,bg=#f2f0e5" 2>/dev/null || true
    tmux display-message -d 5000 "󰂞  ${session}: ${message}" 2>/dev/null || true
  fi

  if [[ -f "/tmp/tmux-remote-state" ]]; then
    local pane_target="${TMUX_PANE:-}"
    if [[ -n "$pane_target" ]]; then
      tmux send-keys -t "$pane_target" "" 2>/dev/null || true
    else
      printf '\a'
    fi
  fi
}

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

cmd_dismiss_session() {
  local session="${1:-}"
  if [[ -z "$session" ]]; then
    echo "Usage: tmux-notify dismiss-session <session-name>" >&2
    exit 1
  fi

  init_file
  lock

  jq --arg sess "$session" '[.[] | select(.session != $sess)]' "$NOTIFY_FILE" > "${NOTIFY_FILE}.tmp" \
    && mv "${NOTIFY_FILE}.tmp" "$NOTIFY_FILE"

  unlock
}

cmd_auto_dismiss() {
  if ! command -v tmux &>/dev/null; then
    return
  fi

  local session window target
  session=$(tmux display-message -p '#S' 2>/dev/null || true)
  window=$(tmux display-message -p '#I' 2>/dev/null || true)

  if [[ -z "$session" || -z "$window" ]]; then
    return
  fi

  target="${session}:${window}"

  init_file
  lock

  local before after
  before=$(jq 'length' "$NOTIFY_FILE")
  jq --arg tgt "$target" '[.[] | select(.target != $tgt)]' "$NOTIFY_FILE" > "${NOTIFY_FILE}.tmp" \
    && mv "${NOTIFY_FILE}.tmp" "$NOTIFY_FILE"
  after=$(jq 'length' "$NOTIFY_FILE")

  unlock

  if [[ "$before" != "$after" ]]; then
    tmux refresh-client -S 2>/dev/null || true
  fi
}

cmd_list() {
  init_file
  cat "$NOTIFY_FILE"
}

cmd_count() {
  init_file
  jq 'length' "$NOTIFY_FILE"
}

cmd_open() {
  if ! command -v tmux &>/dev/null; then
    echo "tmux is not available" >&2
    exit 1
  fi

  local panel_script
  panel_script="$(command -v tmux-opencode-manager)"
  tmux display-popup -w 60 -h 20 -E "$panel_script"
}

cmd_goto() {
  init_file

  local count
  count=$(jq 'length' "$NOTIFY_FILE")
  if [[ "$count" -eq 0 ]]; then
    tmux display-message "No notifications" 2>/dev/null || true
    return
  fi

  local target id
  target=$(jq -r '.[-1].target // empty' "$NOTIFY_FILE")
  id=$(jq -r '.[-1].id' "$NOTIFY_FILE")

  if [[ -n "$id" && "$id" != "null" ]]; then
    cmd_dismiss "$id"
  fi

  if command -v tmux &>/dev/null; then
    tmux refresh-client -S 2>/dev/null || true
    if [[ -n "$target" ]]; then
      tmux select-window -t "$target" 2>/dev/null || true
      tmux switch-client -t "$target" 2>/dev/null || true
    fi
  fi
}

case "${1:-}" in
  add)             shift; cmd_add "$@" ;;
  dismiss)         shift; cmd_dismiss "$@" ;;
  dismiss-session) shift; cmd_dismiss_session "$@" ;;
  auto-dismiss)    cmd_auto_dismiss ;;
  goto)            cmd_goto ;;
  list)            cmd_list ;;
  count)           cmd_count ;;
  open)            cmd_open ;;
  *)
    echo "Usage: tmux-notify <add|dismiss|dismiss-session|auto-dismiss|goto|list|count|open> [args...]" >&2
    exit 1
    ;;
esac
