#!/usr/bin/env bash

# tmux-opencode-manager: OpenCode session manager
# Shows actively generating opencode instances and their notifications, grouped by session.
#
# Keybindings:
#   j/k or arrows  Navigate sessions
#   Enter          Jump to the session's opencode window
#   d              Dismiss all notifications for selected session
#   D              Dismiss all notifications globally
#   q/Escape       Close panel

set -eu

NOTIFY_FILE="${TMUX_NOTIFY_FILE:-/tmp/tmux-notifications.json}"

BOLD=$(tput bold)
DIM=$(tput dim)
RESET=$(tput sgr0)
YELLOW=$(tput setaf 3)
GREEN=$(tput setaf 2)
MAGENTA=$(tput setaf 5)
REVERSE=$(tput rev)

SELECTED=0
SCROLL_OFFSET=0

get_generating_sessions() {
  tmux-opencode-generating 2>/dev/null || echo '[]'
}

get_notifications() {
  if [[ ! -f "$NOTIFY_FILE" ]]; then
    echo '[]'
    return
  fi
  jq 'sort_by(.timestamp) | reverse' "$NOTIFY_FILE" 2>/dev/null || echo '[]'
}

build_sessions() {
  local active="$1"
  local notifications="$2"

  jq -n \
    --argjson active "$active" \
    --argjson notifs "$notifications" \
    '
    ($notifs | group_by(.session) | map({
      key: .[0].session,
      value: {notifs: ., count: length, target: .[0].target}
    }) | from_entries) as $nm |

    ($active | map({key: .session, value: .target}) | from_entries) as $am |

    ([($active // [])[].session] + [($notifs // [])[].session] | unique) as $all |

    [$all[] as $s | {
      session: $s,
      active: ($am[$s] != null),
      target: ($am[$s] // $nm[$s].target // $s),
      notifications: ($nm[$s].notifs // []),
      count: ($nm[$s].count // 0)
    }] |
    sort_by([(.count == 0), (.active | not), .session])
    '
}

render() {
  local sessions="$1"
  local total_sessions total_active
  total_sessions=$(echo "$sessions" | jq 'length')
  total_active=$(echo "$sessions" | jq '[.[] | select(.active)] | length')

  local term_height
  term_height=$(tput lines)
  local max_lines=$((term_height - 6))

  clear

  printf " %s%s  OpenCode Manager%s" "$BOLD" "$MAGENTA" "$RESET"
  if [[ "$total_active" -gt 0 ]]; then
    printf "  %s(%d generating)%s" "$DIM" "$total_active" "$RESET"
  fi
  echo ""
  echo "${DIM}$(printf '%.0s─' $(seq 1 56))${RESET}"

  if [[ "$total_sessions" -eq 0 ]]; then
    echo ""
    echo "  ${DIM}No opencode sessions${RESET}"
    echo ""
    echo "${DIM}$(printf '%.0s─' $(seq 1 56))${RESET}"
    echo "  ${DIM}press q to close${RESET}"
    return
  fi

  if [[ $SELECTED -ge $total_sessions ]]; then
    SELECTED=$((total_sessions - 1))
  fi
  if [[ $SELECTED -lt 0 ]]; then
    SELECTED=0
  fi

  if [[ $SELECTED -lt $SCROLL_OFFSET ]]; then
    SCROLL_OFFSET=$SELECTED
  fi

  local line=0
  local visible_sessions=0

  for ((i = SCROLL_OFFSET; i < total_sessions && line < max_lines; i++)); do
    local entry sess_name active count
    entry=$(echo "$sessions" | jq ".[$i]")
    sess_name=$(echo "$entry" | jq -r '.session')
    active=$(echo "$entry" | jq -r '.active')
    count=$(echo "$entry" | jq -r '.count')

    local prefix="  "
    local bullet="${DIM}○${RESET}"
    local status_text=""
    local notif_text=""

    if [[ $i -eq $SELECTED ]]; then
      prefix=" ${BOLD}▸${RESET}"
    fi

    if [[ "$active" == "true" ]]; then
      bullet="${GREEN}●${RESET}"
      status_text="${GREEN}⏳${RESET}"
    fi

    if [[ "$count" -gt 0 ]]; then
      notif_text="${YELLOW}${count} new${RESET}"
    fi

    local name_display="$sess_name"
    if [[ ${#name_display} -gt 22 ]]; then
      name_display="${name_display:0:21}…"
    fi

    if [[ $i -eq $SELECTED ]]; then
      printf "%s %s ${REVERSE}%-22s${RESET} %s  %s\n" "$prefix" "$bullet" "$name_display" "$status_text" "$notif_text"
    else
      printf "%s %s %-22s %s  %s\n" "$prefix" "$bullet" "$name_display" "$status_text" "$notif_text"
    fi
    line=$((line + 1))

    local max_notifs=3
    local show_count=$count
    if [[ $show_count -gt $max_notifs ]]; then
      show_count=$max_notifs
    fi

    for ((j = 0; j < show_count && line < max_lines; j++)); do
      local message timestamp time_display
      message=$(echo "$entry" | jq -r ".notifications[$j].message")
      timestamp=$(echo "$entry" | jq -r ".notifications[$j].timestamp")
      time_display=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" "+%H:%M" 2>/dev/null || echo "${timestamp:11:5}")

      if [[ ${#message} -gt 34 ]]; then
        message="${message:0:33}…"
      fi

      printf "     %s󰂞 %-34s  %s%s\n" "$DIM" "$message" "$time_display" "$RESET"
      line=$((line + 1))
    done

    if [[ $count -gt $max_notifs && $line -lt $max_lines ]]; then
      printf "     %s… and %d more%s\n" "$DIM" $((count - max_notifs)) "$RESET"
      line=$((line + 1))
    fi

    visible_sessions=$((visible_sessions + 1))
  done

  if [[ $SELECTED -ge $((SCROLL_OFFSET + visible_sessions)) && visible_sessions -gt 0 ]]; then
    SCROLL_OFFSET=$((SELECTED - visible_sessions + 1))
  fi

  if [[ "$total_sessions" -gt $((SCROLL_OFFSET + visible_sessions)) ]]; then
    echo "${DIM}  ↓ $((total_sessions - SCROLL_OFFSET - visible_sessions)) more below${RESET}"
  fi

  echo "${DIM}$(printf '%.0s─' $(seq 1 56))${RESET}"
  echo "  ${DIM}j/k${RESET} navigate  ${DIM}Enter${RESET} goto  ${DIM}d${RESET} dismiss  ${DIM}D${RESET} all  ${DIM}q${RESET} close"
}

dismiss_selected() {
  local sessions="$1"
  local count
  count=$(echo "$sessions" | jq 'length')
  [[ $count -eq 0 ]] && return

  local sess_name
  sess_name=$(echo "$sessions" | jq -r ".[$SELECTED].session")
  tmux-notify dismiss-session "$sess_name"
  tmux refresh-client -S 2>/dev/null || true
}

dismiss_all() {
  tmux-notify dismiss all
  tmux refresh-client -S 2>/dev/null || true
  SELECTED=0
  SCROLL_OFFSET=0
}

goto_selected() {
  local sessions="$1"
  local count
  count=$(echo "$sessions" | jq 'length')
  [[ $count -eq 0 ]] && return

  local target
  target=$(echo "$sessions" | jq -r ".[$SELECTED].target // empty")

  if [[ -n "$target" ]]; then
    dismiss_selected "$sessions"
    tmux select-window -t "$target" 2>/dev/null || true
    tmux switch-client -t "$target" 2>/dev/null || true
    exit 0
  fi
}

tput civis 2>/dev/null || true
trap 'tput cnorm 2>/dev/null || true' EXIT

while true; do
  active=$(get_generating_sessions)
  notifications=$(get_notifications)
  sessions=$(build_sessions "$active" "$notifications")
  render "$sessions"

  IFS= read -rsn1 key

  case "$key" in
    j) SELECTED=$((SELECTED + 1)) ;;
    k) SELECTED=$((SELECTED - 1)) ;;
    '') goto_selected "$sessions" ;;
    d) dismiss_selected "$sessions" ;;
    D) dismiss_all ;;
    q) exit 0 ;;
    $'\e')
      read -rsn1 -t 0.1 next_key || true
      if [[ "${next_key:-}" == "[" ]]; then
        read -rsn1 -t 0.1 arrow_key || true
        case "${arrow_key:-}" in
          A) SELECTED=$((SELECTED - 1)) ;;
          B) SELECTED=$((SELECTED + 1)) ;;
        esac
      else
        exit 0
      fi
      ;;
  esac
done
