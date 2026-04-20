#!/usr/bin/env bash

# @describe OpenCode session manager for tmux
# @meta version 1.0.0

set -eu

NOTIFY_FILE="${TMUX_NOTIFY_FILE:-/tmp/tmux-notifications.json}"
LOCK_FILE="${NOTIFY_FILE}.lock"
OPENCODE_DB="${HOME}/.local/share/opencode/opencode-local.db"
TRIGGER_FILE="/tmp/tmux-opencode-refresh"

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

  # Include a pane if it is CURRENTLY running opencode (command check).
  # Stale @oc-sid/@oc-status options persist after opencode exits, so
  # relying on pane options alone surfaces ghost sessions; we intersect
  # with pane_current_command to filter them out.
  # Uses a tab separator so empty @oc-sid/@oc-status fields (pre-session
  # panes) don't shift columns when parsed.
  local panes
  panes=$(tmux list-panes -a \
    -F '#{session_name}	#{window_index}	#{pane_current_path}	#{pane_id}	#{@oc-sid}	#{@oc-status}	#{pane_current_command}' 2>/dev/null |
    awk -F'\t' '$7 ~ /opencode/ {print $1 " " $2 " " $3 " " $4 " " $5}' | sort -u)

  if [[ -z "$panes" ]]; then
    echo '[]'
    return
  fi

  # DB query for generating status and titles, keyed by session ID.
  # A session is "generating" iff its latest assistant message has no
  # time.completed AND was created within the last 5 minutes. The tight
  # window avoids reporting stuck/orphaned messages (crashed opencode
  # never wrote the completion timestamp) as live generation.
  local db_sessions=""
  if [[ -f "$OPENCODE_DB" ]] && command -v sqlite3 &>/dev/null; then
    local db_query="WITH gen AS (
        SELECT DISTINCT m.session_id
        FROM message m
        WHERE json_extract(m.data, '\$.role') = 'assistant'
          AND (json_extract(m.data, '\$.time.completed') IS NULL
               OR json_extract(m.data, '\$.time.completed') = '')
          AND m.time_created > ((strftime('%s', 'now') - 300) * 1000)
      )
      SELECT s.id, s.directory,
        CASE WHEN gen.session_id IS NOT NULL THEN 'generating' ELSE 'idle' END,
        CASE WHEN s.title LIKE '<%' OR s.title LIKE '{%' OR length(s.title) = 0
          THEN '' ELSE s.title END
      FROM session s
      LEFT JOIN gen ON gen.session_id = s.id
      ORDER BY (gen.session_id IS NOT NULL) DESC, s.time_updated DESC"
    local sep
    sep=$(printf '\x1f')
    db_sessions=$(sqlite3 -separator "$sep" "$OPENCODE_DB" "$db_query" 2>/dev/null || true)
  fi

  local result=""
  local assigned=""
  local sep
  sep=$(printf '\x1f')
  while IFS=' ' read -r sess win path pane_id oc_sid; do
    local status="idle"
    local title=""

    if [[ -n "$oc_sid" ]]; then
      assigned="$assigned $oc_sid"
      if [[ -n "$db_sessions" ]]; then
        while IFS="$sep" read -r s_id s_dir s_status _; do
          if [[ "$s_id" == "$oc_sid" ]]; then
            status="$s_status"
            break
          fi
        done <<<"$db_sessions"
      fi
    elif [[ -n "$db_sessions" ]]; then
      while IFS="$sep" read -r s_id s_dir s_status _; do
        [[ "$s_dir" != "$path" ]] && continue
        case " $assigned " in *" $s_id "*) continue ;; esac
        status="$s_status"
        assigned="$assigned $s_id"
        break
      done <<<"$db_sessions"
    fi

    local pane_title
    pane_title=$(tmux display-message -p -t "$pane_id" '#{pane_title}' 2>/dev/null || true)
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

  tmux list-panes -a \
    -F '#{@oc-sid} #{session_name}:#{window_index} #{pane_id} #{window_active} #{session_attached}' \
    2>/dev/null |
    awk -v sid="$sid" '$1 == sid { print $2, $3, $4, $5; exit }'
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

    # Fallback: resolve pane via @oc-sid (attach-mode where the plugin
    # runs server-side without TMUX_PANE; wrapper sets @oc-sid on
    # attach, oc-sync-sid.sh keeps it in sync).
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
  live_sids="$(tmux list-panes -a -F '#{@oc-sid}' 2>/dev/null | awk 'NF>0' | sort -u | paste -sd, -)"

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
  local ORANGE="#da702c"
  local GREEN="#879a39"
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

  if [[ "$active" -gt 0 ]]; then
    if [[ "${argc_plain:-}" -eq 1 ]]; then
      output="G:${active}"
    else
      output="#[fg=${GREEN},bg=${BG},bold] ⏳ ${active}${RST}"
    fi
  fi

  if [[ "$notifs" -gt 0 ]]; then
    if [[ "${argc_plain:-}" -eq 1 ]]; then
      output="${output} !${notifs}"
    else
      output="${output}#[fg=${ORANGE},bg=${BG},bold] 󰂞 ${notifs}${RST}"
    fi
  fi

  echo "$output"
}

# @cmd Open TUI popup via tmux
open() {
  if ! command -v tmux &>/dev/null; then
    echo "tmux is not available" >&2
    exit 1
  fi

  tmux display-popup -w 60 -h 20 -E "$0 tui"
}

# @cmd Signal the TUI to refresh (used by tmux hooks)
refresh() {
  touch "$TRIGGER_FILE"
}

# @cmd Interactive session manager TUI
tui() {
  local BOLD DIM RESET YELLOW GREEN MAGENTA CYAN REVERSE
  BOLD=$(tput bold)
  DIM=$(tput dim)
  RESET=$(tput sgr0)
  YELLOW=$(tput setaf 3)
  GREEN=$(tput setaf 2)
  MAGENTA=$(tput setaf 5)
  CYAN=$(tput setaf 6)
  REVERSE=$(tput rev)

  local SESSIONS=""
  local RENDER_LINES=()
  local SEPARATOR
  SEPARATOR=$(printf '%.0s─' {1..78})
  local SELECTED=0
  local SCROLL_OFFSET=0
  local NEEDS_REFRESH=1
  local NEEDS_RENDER=0
  local WATCHER_PID=""

  trap 'NEEDS_REFRESH=1' USR1

  _tui_start_watcher() {
    touch "$TRIGGER_FILE"
    local tui_pid=$$
    local targets=("$NOTIFY_FILE" "$TRIGGER_FILE")
    [[ -f "${OPENCODE_DB}-wal" ]] && targets+=("${OPENCODE_DB}-wal")

    (fswatch --one-per-batch --latency=0.3 "${targets[@]}" 2>/dev/null | while read -r _; do
      kill -USR1 "$tui_pid" 2>/dev/null || break
    done) &
    WATCHER_PID=$!
  }

  # shellcheck disable=SC2329 # invoked indirectly via trap EXIT
  _tui_stop_watcher() {
    if [[ -n "${WATCHER_PID:-}" ]]; then
      pkill -P "$WATCHER_PID" 2>/dev/null || true
      kill "$WATCHER_PID" 2>/dev/null || true
      wait "$WATCHER_PID" 2>/dev/null || true
    fi
  }

  _tui_load_state() {
    local sess_data notif_data
    sess_data=$(_get_sessions)
    notif_data=$(_get_notifications)
    SESSIONS=$(_build_tui_sessions "$sess_data" "$notif_data")

    RENDER_LINES=()
    local line
    while IFS= read -r line; do
      RENDER_LINES+=("$line")
    done < <(echo "$SESSIONS" | jq -r '
      "\(length)\t\([.[] | select(.status == "generating")] | length)\t\([.[] | select(.status == "idle")] | length)",
      (group_by(.session)[] |
        "S\t\(.[0].session)\t\([.[] | select(.status == "generating")] | length)\t\([.[] | select(.status == "idle")] | length)\t\([.[] | .count] | add // 0)",
        (.[] |
          "E\t\(.target | split(":") | .[1])\t\(.status)\t\(.count)\t\(.title[:40] | if length >= 40 then . + "…" else . end)",
          (.notifications[:3][] |
            "N\t\(.message[:36] | if length >= 36 then . + "…" else . end)\t\(.timestamp[11:16])"
          ),
          (if .count > 3 then "X\t\(.count - 3)" else empty end)
        )
      )
    ')

    NEEDS_RENDER=1
  }

  _build_tui_sessions() {
    local sess_json="$1"
    local notifications="$2"

    jq -n \
      --argjson sess "$sess_json" \
      --argjson notifs "$notifications" \
      '
      ($notifs | group_by(.target) | map({
        key: .[0].target,
        value: {notifs: ., count: length, session: .[0].session}
      }) | from_entries) as $nm |

      ($sess | map({key: .target, value: {session: .session, status: .status, title: .title}}) | from_entries) as $sm |

      ([($sess // [])[].target] + [($notifs // [])[].target] | map(select(. != null and . != "")) | unique) as $all |

      [$all[] as $t | {
        session: ($sm[$t].session // $nm[$t].session // ($t | split(":") | .[0])),
        target: $t,
        status: ($sm[$t].status // "none"),
        title: ($sm[$t].title // ""),
        notifications: ($nm[$t].notifs // []),
        count: ($nm[$t].count // 0)
      }] |
      sort_by([(.count == 0 and .status != "generating" and .status != "idle"), (.status != "generating"), (.status != "idle"), .target])
      '
  }

  _render() {
    local total_sessions total_generating total_idle
    IFS=$'\t' read -r total_sessions total_generating total_idle <<< "${RENDER_LINES[0]}"

    local max_lines=$(( ${LINES:-30} - 6 ))

    clear

    printf " %s%s  OpenCode Manager%s" "$BOLD" "$MAGENTA" "$RESET"
    local summary=""
    [[ "$total_generating" -gt 0 ]] && summary="${total_generating} generating"
    if [[ "$total_idle" -gt 0 ]]; then
      [[ -n "$summary" ]] && summary="${summary}, "
      summary="${summary}${total_idle} idle"
    fi
    [[ -n "$summary" ]] && printf "  %s(%s)%s" "$DIM" "$summary" "$RESET"
    echo ""
    echo "${DIM}${SEPARATOR}${RESET}"

    if [[ "$total_sessions" -eq 0 ]]; then
      echo ""
      echo "  ${DIM}No opencode sessions${RESET}"
      echo ""
      echo "${DIM}${SEPARATOR}${RESET}"
      echo "  ${DIM}press q to close${RESET}"
      return
    fi

    [[ $SELECTED -ge $total_sessions ]] && SELECTED=$((total_sessions - 1))
    [[ $SELECTED -lt 0 ]] && SELECTED=0
    [[ $SELECTED -lt $SCROLL_OFFSET ]] && SCROLL_OFFSET=$SELECTED

    local drawn=0
    local visible=0
    local entry_idx=0
    local ri=1

    while [[ $ri -lt ${#RENDER_LINES[@]} ]]; do
      local rtype rfield1 rfield2 rfield3 rfield4
      IFS=$'\t' read -r rtype rfield1 rfield2 rfield3 rfield4 <<< "${RENDER_LINES[$ri]}"

      if [[ "$rtype" == "S" ]]; then
        [[ $drawn -ge $max_lines ]] && break
        local s_name="$rfield1" s_gen="$rfield2" s_idle="$rfield3" s_notifs="$rfield4"
        local s_summary=""
        [[ "$s_gen" -gt 0 ]] && s_summary="${s_gen} generating"
        if [[ "$s_idle" -gt 0 ]]; then
          [[ -n "$s_summary" ]] && s_summary="${s_summary}, "
          s_summary="${s_summary}${s_idle} idle"
        fi
        local s_notif_text=""
        [[ "$s_notifs" -gt 0 ]] && s_notif_text="${YELLOW}${s_notifs} new${RESET}"

        if [[ $drawn -gt 0 ]]; then
          echo ""
          drawn=$((drawn + 1))
        fi
        printf "  %s%s%s  %s%s%s  %s\n" "$BOLD" "$s_name" "$RESET" "$DIM" "$s_summary" "$RESET" "$s_notif_text"
        drawn=$((drawn + 1))
        ri=$((ri + 1))
        continue
      fi

      if [[ "$rtype" != "E" ]]; then
        ri=$((ri + 1))
        continue
      fi

      local win_idx="$rfield1" status="$rfield2" count="$rfield3" title="$rfield4"

      if [[ $entry_idx -lt $SCROLL_OFFSET ]]; then
        entry_idx=$((entry_idx + 1))
        ri=$((ri + 1))
        while [[ $ri -lt ${#RENDER_LINES[@]} ]]; do
          IFS=$'\t' read -r rtype _ <<< "${RENDER_LINES[$ri]}"
          [[ "$rtype" == "E" || "$rtype" == "S" ]] && break
          ri=$((ri + 1))
        done
        continue
      fi

      [[ $drawn -ge $max_lines ]] && break

      local bullet="${DIM}○${RESET}" status_text="" notif_text=""

      case "$status" in
        generating) bullet="${GREEN}●${RESET}"; status_text="${GREEN}⏳${RESET}" ;;
        idle) bullet="${CYAN}●${RESET}"; status_text="${DIM}idle${RESET}" ;;
      esac

      [[ "$count" -gt 0 ]] && notif_text="${YELLOW}${count} new${RESET}"

      local title_display="${title:-}"
      [[ -z "$title_display" ]] && title_display="${DIM}-${RESET}"

      if [[ $entry_idx -eq $SELECTED ]]; then
        printf "  %s▸%s %s ${REVERSE}:%-2s%s %-40s${RESET} %s  %s\n" "$BOLD" "$RESET" "$bullet" "$win_idx" "" "$title_display" "$status_text" "$notif_text"
      else
        printf "    %s :%-2s %-40s %s  %s\n" "$bullet" "$win_idx" "$title_display" "$status_text" "$notif_text"
      fi
      drawn=$((drawn + 1))
      ri=$((ri + 1))

      while [[ $ri -lt ${#RENDER_LINES[@]} && $drawn -lt $max_lines ]]; do
        IFS=$'\t' read -r rtype rfield1 rfield2 <<< "${RENDER_LINES[$ri]}"
        if [[ "$rtype" == "N" ]]; then
          printf "        %s󰭞 %-38s  %s%s\n" "$DIM" "$rfield1" "$rfield2" "$RESET"
          drawn=$((drawn + 1))
        elif [[ "$rtype" == "X" ]]; then
          printf "        %s… and %s more%s\n" "$DIM" "$rfield1" "$RESET"
          drawn=$((drawn + 1))
        else
          break
        fi
        ri=$((ri + 1))
      done

      entry_idx=$((entry_idx + 1))
      visible=$((visible + 1))
    done

    [[ $SELECTED -ge $((SCROLL_OFFSET + visible)) && $visible -gt 0 ]] && SCROLL_OFFSET=$((SELECTED - visible + 1))

    if [[ "$total_sessions" -gt $((SCROLL_OFFSET + visible)) ]]; then
      echo "${DIM}  ↓ $((total_sessions - SCROLL_OFFSET - visible)) more below${RESET}"
    fi

    echo "${DIM}${SEPARATOR}${RESET}"
    echo "  ${DIM}j/k${RESET} navigate  ${DIM}Enter${RESET} goto  ${DIM}d${RESET} dismiss  ${DIM}D${RESET} all  ${DIM}q${RESET} close"
  }

  _dismiss_selected() {
    local count
    count=$(echo "$SESSIONS" | jq 'length')
    [[ $count -eq 0 ]] && return

    local sel_target
    sel_target=$(echo "$SESSIONS" | jq -r ".[$SELECTED].target")

    _init_file
    _lock
    jq --arg tgt "$sel_target" '[.[] | select(.target != $tgt)]' "$NOTIFY_FILE" >"${NOTIFY_FILE}.tmp" &&
      mv "${NOTIFY_FILE}.tmp" "$NOTIFY_FILE"
    _unlock
    tmux refresh-client -S 2>/dev/null || true
    NEEDS_REFRESH=1
  }

  _dismiss_all() {
    _init_file
    _lock
    echo '[]' >"$NOTIFY_FILE"
    _unlock
    tmux refresh-client -S 2>/dev/null || true
    SELECTED=0
    SCROLL_OFFSET=0
    NEEDS_REFRESH=1
  }

  _goto_selected() {
    local count
    count=$(echo "$SESSIONS" | jq 'length')
    [[ $count -eq 0 ]] && return

    local target notif_count
    target=$(echo "$SESSIONS" | jq -r ".[$SELECTED].target // empty")
    notif_count=$(echo "$SESSIONS" | jq -r ".[$SELECTED].count")

    if [[ -n "$target" ]]; then
      [[ "$notif_count" -gt 0 ]] && _dismiss_selected
      # Target the CALLER's client explicitly. Inside a display-popup,
      # tmux picks "the client currently in use" for unscoped commands,
      # which is the popup's own client — not the user's terminal.
      # opencode-manager.nix passes TMUX_OPENCODE_CALLER_TTY via `-e`.
      if [[ -n "${TMUX_OPENCODE_CALLER_TTY:-}" ]]; then
        tmux switch-client -c "$TMUX_OPENCODE_CALLER_TTY" -t "$target" 2>/dev/null || true
      else
        tmux select-window -t "$target" 2>/dev/null || true
        tmux switch-client -t "$target" 2>/dev/null || true
      fi
      exit 0
    fi
  }

  tput civis 2>/dev/null || true
  _tui_start_watcher
  trap '_tui_stop_watcher; tput cnorm 2>/dev/null || true' EXIT

  while true; do
    if [[ $NEEDS_REFRESH -eq 1 ]]; then
      NEEDS_REFRESH=0
      _tui_load_state
    fi

    if [[ $NEEDS_RENDER -eq 1 ]]; then
      NEEDS_RENDER=0
      _render
    fi

    local key=""
    local rc=0
    IFS= read -rsn1 -t 2 key || rc=$?

    if [[ $rc -gt 128 ]]; then
      continue
    fi

    case "$key" in
      j) SELECTED=$((SELECTED + 1)); NEEDS_RENDER=1 ;;
      k) SELECTED=$((SELECTED - 1)); NEEDS_RENDER=1 ;;
      '') _goto_selected ;;
      d) _dismiss_selected ;;
      D) _dismiss_all ;;
      q) exit 0 ;;
      $'\e')
        read -rsn1 -t 0.1 next_key || true
        if [[ "${next_key:-}" == "[" ]]; then
          read -rsn1 -t 0.1 arrow_key || true
          case "${arrow_key:-}" in
            A) SELECTED=$((SELECTED - 1)); NEEDS_RENDER=1 ;;
            B) SELECTED=$((SELECTED + 1)); NEEDS_RENDER=1 ;;
          esac
        else
          exit 0
        fi
        ;;
    esac
  done
}

eval "$(argc --argc-eval "$0" "$@")"
