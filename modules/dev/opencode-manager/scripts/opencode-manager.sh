#!/usr/bin/env bash

# @describe OpenCode session manager for tmux
# @meta version 1.0.0

set -eu

NOTIFY_FILE="${TMUX_NOTIFY_FILE:-/tmp/tmux-notifications.json}"
LOCK_FILE="${NOTIFY_FILE}.lock"

_init_file() {
  if [[ ! -f "$NOTIFY_FILE" ]]; then
    echo '[]' >"$NOTIFY_FILE"
  fi
}

_lock() {
  local attempts=0
  while ! mkdir "$LOCK_FILE" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [[ $attempts -gt 50 ]]; then
      rm -rf "$LOCK_FILE"
    fi
    sleep 0.01
  done
}

_unlock() {
  rm -rf "$LOCK_FILE"
}

# Returns JSON array of opencode panes with generating/idle status:
#   [{"session": "...", "target": "session:window", "status": "generating|idle"}]
_get_sessions() {
  if ! command -v tmux &>/dev/null; then
    echo '[]'
    return
  fi

  # Include a pane if it is CURRENTLY running opencode: @oc-sid/@oc-status
  # persist after opencode exits, so pane options alone surface ghosts.
  # @oc-status carries opencode's own session status (busy/idle/retry),
  # published by the tmux-notifier plugin -- no DB round trip, and no
  # guessing liveness from message timestamps.
  local panes
  panes=$(tmux list-panes -a \
    -F '#{session_name}	#{window_index}	#{@oc-status}	#{pane_current_command}	#{pane_title}' 2>/dev/null |
    awk -F'\t' -v OFS='\t' '$4 ~ /opencode/ {print $1, $2, $3, $5}' | sort -u)

  if [[ -z "$panes" ]]; then
    echo '[]'
    return
  fi

  local result=""
  while IFS=$'\t' read -r sess win oc_status pane_title; do
    local status="idle"
    case "$oc_status" in
      busy | retry) status="generating" ;;
    esac

    local title=""
    if [[ "$pane_title" == OC\ \|\ * ]]; then
      title="${pane_title#OC | }"
    fi

    printf -v _entry '%s\t%s\t%s\t%s\n' "$sess" "$win" "$status" "$title"
    result+="$_entry"
  done <<<"$panes"

  if [[ -z "${result:-}" ]]; then
    echo '[]'
    return
  fi

  echo "$result" | awk -F'\t' 'NF >= 3 {printf "%s\t%s\t%s\t%s\n", $1, $2, $3, $4}' |
    jq -Rn '[inputs | split("\t") | {session: .[0], target: (.[0] + ":" + .[1]), status: .[2], title: (.[3] // "")}]'
}

_get_notifications() {
  if [[ ! -f "$NOTIFY_FILE" ]]; then
    echo '[]'
    return
  fi
  jq 'sort_by(.timestamp) | reverse' "$NOTIFY_FILE" 2>/dev/null || echo '[]'
}

# @cmd Notification management
notify() { :; }

# Resolve a tmux target (session:window) for a given opencode session ID
# by scanning pane options for a matching @oc-sid.
# Exit 0 + stdout: "session:window [paneId] [window_active] [session_attached]"
# Exit 1: no match
_resolve_target_by_sid() {
  local sid="$1"
  [[ -z "$sid" ]] && return 1

  # Pane options outlive the opencode process, so a pane that has since
  # returned to a shell still advertises its old @oc-sid. Match only panes
  # actually running opencode, or notifications route to a dead pane.
  tmux list-panes -a \
    -F '#{@oc-sid}	#{session_name}:#{window_index}	#{pane_id}	#{window_active}	#{session_attached}	#{pane_current_command}' \
    2>/dev/null |
    awk -F'\t' -v sid="$sid" '$1 == sid && $6 ~ /opencode/ { print $2, $3, $4, $5; exit }'
}

# @cmd Add a notification
# @option --event <EVENT>         Event type (complete, permission, error, question)
# @option --session-id <SID>      OpenCode session ID (resolves via @oc-sid when no --pane-id)
# @option --pane-id <PANE>        tmux pane id (preferred when provided)
# @flag --require-target          Drop notification if no tmux target resolves (filters out `opencode run`)
# @arg message!                   Notification message
notify::add() {
  local event="${argc_event:-}"
  local sid="${argc_session_id:-}"
  local pane_id_arg="${argc_pane_id:-}"
  local require_target="${argc_require_target:-0}"
  # shellcheck disable=SC2154 # set by argc
  local message="$argc_message"

  if [[ -n "$event" ]]; then
    case "$event" in
      complete | permission | error | question) ;;
      *) exit 0 ;;
    esac
  fi

  local id timestamp session window target pane_id
  id="$(printf '%s%s' "$(date +%s)" "$$" | shasum | head -c 8)"
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  session=""
  window=""
  target=""
  pane_id=""
  local pane_active="" session_attached=""

  if command -v tmux &>/dev/null; then
    local primary_pane="${pane_id_arg:-${TMUX_PANE:-}}"

    # Preferred: a real tmux pane id (plugin forwards TMUX_PANE via
    # --pane-id in standalone mode; falls back to inherited TMUX_PANE
    # for manual CLI callers). Most reliable signal — no DB lookup.
    if [[ -n "$primary_pane" ]]; then
      session="$(tmux display-message -p -t "$primary_pane" '#S' 2>/dev/null || true)"
      window="$(tmux display-message -p -t "$primary_pane" '#I' 2>/dev/null || true)"
      pane_active="$(tmux display-message -p -t "$primary_pane" '#{window_active}' 2>/dev/null || true)"
      session_attached="$(tmux display-message -p -t "$primary_pane" '#{session_attached}' 2>/dev/null || true)"
      pane_id="$primary_pane"
      if [[ -n "$session" && -n "$window" ]]; then
        target="${session}:${window}"
      fi
    fi

    # Fallback: resolve pane via @oc-sid — set by the tmux-notifier
    # plugin from session events (per-pane instances), or by the
    # wrapper's pre-launch resolution in attach mode.
    # Never fall back to bare `tmux display-message -p '#S'` — that
    # queries whichever client is currently attached, the root bug
    # this plugin fixes.
    if [[ -z "$target" && -n "$sid" ]]; then
      local resolved
      resolved="$(_resolve_target_by_sid "$sid" || true)"
      if [[ -n "$resolved" ]]; then
        read -r target pane_id pane_active session_attached <<<"$resolved"
        session="${target%%:*}"
        window="${target##*:}"
      fi
    fi
  fi

  # Drop notification when caller requires a target and none resolved.
  # Used by the opencode plugin to filter out sessions with no tmux
  # home (e.g., `opencode run`, sessions in closed panes).
  if [[ "$require_target" == "1" && -z "$target" ]]; then
    exit 0
  fi

  session="${session:-opencode}"

  # Suppress when the resolved pane is focused in an attached client.
  if [[ "$pane_active" == "1" && "${session_attached:-0}" -gt 0 ]]; then
    exit 0
  fi

  _init_file
  _lock

  local entry
  entry=$(jq -n \
    --arg id "$id" \
    --arg ts "$timestamp" \
    --arg sess "$session" \
    --arg msg "$message" \
    --arg tgt "$target" \
    --arg sid "$sid" \
    --arg ev "${event:-}" \
    '{id: $id, timestamp: $ts, session: $sess, message: $msg, target: $tgt, sessionID: $sid, event: $ev}')

  # Dedupe by (sessionID, event) when we have a sessionID — the same
  # opencode session firing the same event twice in quick succession
  # should collapse to one entry. Otherwise fall back to target-based
  # dedupe for legacy TMUX_PANE-only callers (which still produce
  # distinct targets per pane).
  if [[ -n "$sid" ]]; then
    jq --argjson entry "$entry" \
      '[.[] | select(.sessionID != $entry.sessionID or .event != $entry.event)] + [$entry]' \
      "$NOTIFY_FILE" >"${NOTIFY_FILE}.tmp" &&
      mv "${NOTIFY_FILE}.tmp" "$NOTIFY_FILE"
  else
    jq --argjson entry "$entry" \
      '[.[] | select(.target != $entry.target or $entry.target == "")] + [$entry]' \
      "$NOTIFY_FILE" >"${NOTIFY_FILE}.tmp" &&
      mv "${NOTIFY_FILE}.tmp" "$NOTIFY_FILE"
  fi

  _unlock

  if command -v tmux &>/dev/null; then
    tmux refresh-client -S 2>/dev/null || true
    tmux set -g message-style "fg=#da702c,bg=#f2f0e5" 2>/dev/null || true
    tmux display-message -d 5000 "󰂞  ${session}: ${message}" 2>/dev/null || true
  fi

  if [[ -f "/tmp/tmux-remote-state" ]]; then
    if [[ -n "${TMUX_PANE:-}" ]]; then
      tmux send-keys -t "$TMUX_PANE" "" 2>/dev/null || true
    else
      printf '\a'
    fi
  fi
}

# @cmd Dismiss notification(s)
# @arg target!   ID or 'all'
notify::dismiss() {
  # shellcheck disable=SC2154 # set by argc
  local target="$argc_target"

  _init_file
  _lock

  if [[ "$target" == "all" ]]; then
    echo '[]' >"$NOTIFY_FILE"
  else
    jq --arg id "$target" '[.[] | select(.id != $id)]' "$NOTIFY_FILE" >"${NOTIFY_FILE}.tmp" &&
      mv "${NOTIFY_FILE}.tmp" "$NOTIFY_FILE"
  fi

  _unlock
}

# @cmd Dismiss all notifications for a session
# @arg session!   Session name
notify::dismiss_session() {
  # shellcheck disable=SC2154 # set by argc
  local session="$argc_session"

  _init_file
  _lock

  jq --arg sess "$session" '[.[] | select(.session != $sess)]' "$NOTIFY_FILE" >"${NOTIFY_FILE}.tmp" &&
    mv "${NOTIFY_FILE}.tmp" "$NOTIFY_FILE"

  _unlock
}

# @cmd Dismiss notifications whose opencode sessionID is no longer claimed
#      by any live tmux pane (via @oc-sid). Called by the after-kill-pane
#      hook — since the pane is already gone by the time we fire, we can't
#      look up its @oc-sid anymore; instead we reconcile the notification
#      set against the currently-live set of claimed session IDs.
notify::dismiss_orphans() {
  _init_file
  _lock

  local live_sids
  # Only sids claimed by a pane still running opencode count as live; a stale
  # option on an exited pane would otherwise pin its notifications forever.
  live_sids="$(tmux list-panes -a -F '#{@oc-sid}	#{pane_current_command}' 2>/dev/null |
    awk -F'\t' '$1 != "" && $2 ~ /opencode/ { print $1 }' | sort -u | paste -sd, -)"

  local before after
  before=$(jq 'length' "$NOTIFY_FILE")
  jq --arg live "$live_sids" '
    ($live | split(",") | map(select(length > 0))) as $alive |
    [.[] | select(.sessionID == "" or (.sessionID | IN($alive[])))]
  ' "$NOTIFY_FILE" >"${NOTIFY_FILE}.tmp" && mv "${NOTIFY_FILE}.tmp" "$NOTIFY_FILE"
  after=$(jq 'length' "$NOTIFY_FILE")

  _unlock

  if [[ "$before" != "$after" ]] && command -v tmux &>/dev/null; then
    tmux refresh-client -S 2>/dev/null || true
  fi
}

# @cmd Dismiss notifications for a specific tmux pane (parses hook args)
#      Accepts tmux after-kill-pane's "hook_arguments" string like "-t %123".
# @arg args!   hook_arguments string from tmux
notify::dismiss_pane() {
  # shellcheck disable=SC2154 # set by argc
  local args="$argc_args"

  local pane_id=""
  if [[ "$args" =~ -t[[:space:]]+(%[0-9]+) ]]; then
    pane_id="${BASH_REMATCH[1]}"
  fi

  if [[ -n "$pane_id" ]]; then
    local sid
    sid="$(tmux show-options -pv -t "$pane_id" @oc-sid 2>/dev/null || true)"
    if [[ -n "$sid" ]]; then
      _init_file
      _lock
      jq --arg sid "$sid" '[.[] | select(.sessionID != $sid)]' "$NOTIFY_FILE" >"${NOTIFY_FILE}.tmp" &&
        mv "${NOTIFY_FILE}.tmp" "$NOTIFY_FILE"
      _unlock
      command -v tmux &>/dev/null && tmux refresh-client -S 2>/dev/null || true
      return
    fi
  fi

  notify::dismiss_orphans
}

# @cmd Dismiss notifications for a specific target
# @arg target!   Target (session:window)
notify::dismiss_target() {
  # shellcheck disable=SC2154 # set by argc
  local target="$argc_target"

  _init_file
  _lock

  local before after
  before=$(jq 'length' "$NOTIFY_FILE")
  jq --arg tgt "$target" '[.[] | select(.target != $tgt)]' "$NOTIFY_FILE" >"${NOTIFY_FILE}.tmp" &&
    mv "${NOTIFY_FILE}.tmp" "$NOTIFY_FILE"
  after=$(jq 'length' "$NOTIFY_FILE")

  _unlock

  if [[ "$before" != "$after" ]]; then
    tmux refresh-client -S 2>/dev/null || true
  fi
}

# @cmd Auto-dismiss notifications for the current tmux window
notify::auto_dismiss() {
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

  _init_file
  _lock

  local before after
  before=$(jq 'length' "$NOTIFY_FILE")
  jq --arg tgt "$target" '[.[] | select(.target != $tgt)]' "$NOTIFY_FILE" >"${NOTIFY_FILE}.tmp" &&
    mv "${NOTIFY_FILE}.tmp" "$NOTIFY_FILE"
  after=$(jq 'length' "$NOTIFY_FILE")

  _unlock

  if [[ "$before" != "$after" ]]; then
    tmux refresh-client -S 2>/dev/null || true
  fi
}

# @cmd Jump to the most recent notification
notify::goto() {
  _init_file

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
    _init_file
    _lock
    jq --arg id "$id" '[.[] | select(.id != $id)]' "$NOTIFY_FILE" >"${NOTIFY_FILE}.tmp" &&
      mv "${NOTIFY_FILE}.tmp" "$NOTIFY_FILE"
    _unlock
  fi

  if command -v tmux &>/dev/null; then
    tmux refresh-client -S 2>/dev/null || true
    if [[ -n "$target" ]]; then
      if [[ -n "${TMUX_OPENCODE_CALLER_TTY:-}" ]]; then
        tmux switch-client -c "$TMUX_OPENCODE_CALLER_TTY" -t "$target" 2>/dev/null || true
      else
        tmux select-window -t "$target" 2>/dev/null || true
        tmux switch-client -t "$target" 2>/dev/null || true
      fi
    fi
  fi
}

# @cmd List all notifications as JSON
notify::list() {
  _init_file
  cat "$NOTIFY_FILE"
}

# @cmd Output notification count
notify::count() {
  _init_file
  jq 'length' "$NOTIFY_FILE"
}

# @cmd List opencode sessions as JSON (generating and idle)
sessions() {
  _get_sessions
}

# @cmd Show status bar widget
# @flag --plain   Plain text output for remote/minimal displays
widget() {
  local BG="#f2f0e5"
  local FG="#100f0f"
  local PURPLE="#8b7ec8"
  local ORANGE="#da702c"
  local WHITE="#fffcf0"
  local RST="#[fg=${FG},bg=${BG},nobold,noitalics,nounderscore,nodim]"

  local all_sessions
  all_sessions=$(_get_sessions 2>/dev/null || echo '[]')

  local active
  active=$(echo "$all_sessions" | jq '[.[] | select(.status == "generating")] | length' 2>/dev/null || echo 0)

  local notifs=0
  if [[ -f "$NOTIFY_FILE" ]]; then
    notifs=$(jq 'length' "$NOTIFY_FILE" 2>/dev/null || echo 0)
  fi

  local output=""

  if [[ "${argc_plain:-}" -eq 1 ]]; then
    if [[ "$active" -gt 0 ]]; then
      output="G:${active}"
    fi
    if [[ "$notifs" -gt 0 ]]; then
      output="${output} !${notifs}"
    fi
  else
    # Urgency shift: orange when notifications need attention, purple otherwise.
    local badge_bg="${PURPLE}"
    if [[ "$notifs" -gt 0 ]]; then
      badge_bg="${ORANGE}"
    fi

    local body=""
    if [[ "$active" -gt 0 ]]; then
      body="${body}#[fg=${WHITE},bg=${badge_bg},bold]  ${active}"
    fi
    if [[ "$notifs" -gt 0 ]]; then
      body="${body}#[fg=${WHITE},bg=${badge_bg},bold]  ${notifs}"
    fi

    if [[ -n "$body" ]]; then
      # Powerline rounded ends form a pill:  on the left,  on the right.
      output="#[fg=${badge_bg},bg=${BG}]${body} #[fg=${badge_bg},bg=${BG}]${RST} "
    fi
  fi

  echo "$output"
}

eval "$(argc --argc-eval "$0" "$@")"
