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

# @cmd Interactive session manager (fzf picker)
# @flag --list   Emit picker rows; internal, used by fzf's reload binds
tui() {
  local DIM=$'\033[2m' RST=$'\033[0m'
  local GRN=$'\033[32m' YEL=$'\033[33m' RED=$'\033[31m'

  # The popup is its own tmux client, so #S inside it is the popup — not the
  # pane you opened it from. opencode-manager.nix passes the caller's tty via
  # `-e`, which is the only reliable handle on "where am I".
  #
  # Two calls, because -c does NOT retarget #S: only client_* formats resolve
  # against the client, everything else expands against the *calling* pane
  # (verified — a single `-c ... -p '#S:#{window_index}'` returns the popup's
  # own session). So: ask the client for its session, then ask that session
  # for its current window.
  _tui_current() {
    [[ -z "${TMUX_OPENCODE_CALLER_TTY:-}" ]] && return 0
    local sess
    sess=$(tmux display-message -c "$TMUX_OPENCODE_CALLER_TTY" -p '#{client_session}' 2>/dev/null || true)
    [[ -z "$sess" ]] && return 0
    tmux display-message -t "$sess" -p '#S:#{window_index}' 2>/dev/null || true
  }

  # One selectable row per opencode pane: "<target>\t<display>". Layout and
  # glyphs match the session picker (cli/tmux/session-picker.nix) so the two
  # popups read the same: worktree sessions nest under their root with ├─/└─
  # connectors, and ◍ busy · ● done · ⏸ permission · ? question · ‼ error.
  # A pending notification means "needs YOU" and outranks a busy spinner.
  #
  # Everything inside a root hangs off one stem in column 0, so a root's own
  # extra panes and its worktrees read as one group. A worktree branches off it
  # with ├─ (└─ for the last); an extra pane of a session is just the stem
  # continuing, unbranched. Depth needs no marker — a nested pane draws its
  # parent's rail too, so "│  └" is a pane of the worktree above while a bare
  # "│" is a pane of the root. Every rail closes with └ on its last row. The
  # window index is never shown: you pick a pane by its title, and the index
  # fzf needs to switch to it is in hidden field 1.
  #
  # Both the rail and the tree hide text a name search needs — a rail row shows
  # no name at all, and a nested row shows only its leaf. So filtering drops
  # both: fzf exports FZF_PROMPT and FZF_QUERY to the children it spawns for
  # reload, so pressing "/" re-renders as a flat list of fully-qualified names
  # and Esc restores the tree. Without this, searching "telepatia" would
  # quietly return one row when nine match.
  #
  # Order is the tree, not urgency: the glyph already carries urgency, and a
  # stable order means the 2s auto-refresh never reshuffles rows under the
  # cursor. prefix+N (notify goto) is the urgency-first entry point.
  #
  # Targets are the union of live opencode panes and notification targets: a
  # notification whose pane already exited still has to be visible to be
  # dismissable.
  #
  # ponytail: no per-tmux-session group headers, no notification message
  # previews, no counts, no "N more" — the glyph says what needs attention and
  # Enter takes you to the pane that has the detail.
  _tui_list() {
    local collapse=1
    if [[ -n "${FZF_QUERY:-}" || "${FZF_PROMPT:-}" == "/ " ]]; then
      collapse=0
    fi

    jq -rn \
      --argjson sess "$(_get_sessions)" \
      --argjson notifs "$(_get_notifications)" \
      --argjson collapse "$collapse" \
      --arg cur "$(_tui_current)" \
      --arg dim "$DIM" --arg rst "$RST" \
      --arg grn "$GRN" --arg yel "$YEL" --arg red "$RED" \
      '
      def rank:
        if   . == "error"      then 4
        elif . == "question"   then 3
        elif . == "permission" then 2
        else 1 end;

      ($notifs | group_by(.target) | map({
        key: .[0].target,
        value: ([.[] | .event | rank] | max)
      }) | from_entries) as $nrank |
      ($sess | map({key: .target, value: .}) | from_entries) as $live |

      ([$sess[].target] + [$notifs[].target]
        | map(select(. != null and . != "")) | unique) as $targets |

      [ $targets[]
        | . as $t
        | ($t | split(":")) as $p
        | ($p[0]) as $s
        | {
            target: $t,
            sess:   $s,
            win:    (($p[1] // "") | tonumber? // 0),
            root:   ($s | split("/") | .[0]),
            leaf:   ($s | split("/") | .[-1]),
            status: ($live[$t].status // "none"),
            title:  ($live[$t].title  // ""),
            rank:   ($nrank[$t] // 0)
          }
      ]
      | sort_by([.root, (if .sess == .root then 0 else 1 end), .sess, .win]) as $rows
      | ([ $rows[] | select(.sess == .root) | .root ] | unique) as $roots
      | ( $rows | map(select(.sess != .root)) | group_by(.root)
          | map({key: .[0].root, value: (.[-1].sess)}) | from_entries ) as $lastkid
      | [ $rows
          | to_entries[]
          | .key as $i
          | .value as $r
          | ((if $i == 0 then null else $rows[$i - 1] end)
             | if . == null then true else .sess != $r.sess end) as $isfirst
          | (($rows[$i + 1] // null)
             | if . == null then true else .root != $r.root end) as $islastinroot
          | (($rows[$i + 1] // null)
             | if . == null then true else .sess != $r.sess end) as $islastinsess
          | (if $r.sess == $r.root or ($roots | index($r.root) | not) then ""
             elif $lastkid[$r.root] == $r.sess then "└─"
             else "├─" end) as $conn
          | (if $conn == "" then
               (if $islastinroot then "└" else "│" end)
             else
               (if $islastinroot then " " else "│" end)
               + "  " + (if $islastinsess then "└" else "│" end)
             end) as $panebar
          | (if $collapse == 0 then
               { plain: $r.sess, body: $r.sess }
             elif ($isfirst | not) then
               { plain: $panebar,
                 body:  ($dim + $panebar + $rst) }
             elif $conn == "" then
               { plain: $r.sess, body: $r.sess }
             else
               { plain: ($conn + " " + $r.leaf),
                 body:  ($dim + $conn + $rst + " " + $r.leaf) }
             end) as $c
          | $r + $c
        ] as $out
      | ([ $out[] | .plain | length ] | max // 0) as $w
      | $out[]
      | (if   .rank == 4              then $red + "‼"
         elif .rank == 3              then $yel + "?"
         elif .rank == 2              then $yel + "⏸"
         elif .rank == 1              then $grn + "●"
         elif .status == "generating" then $dim + "◍"
         else " " end) as $glyph
      | (if .target == $cur then $grn + "●" + $rst else " " end) as $mark
      | (" " * ($w - (.plain | length) + 2)) as $pad
      | (if .title == "" then "—" else .title end) as $title
      | "\(.target)\t\($mark) \($glyph)\($rst)  \(.body)\($pad)\($dim)\($title)\($rst)"
      '
  }

  if [[ "${argc_list:-0}" -eq 1 ]]; then
    _tui_list
    exit 0
  fi

  local self="$0"
  local list cur pos=1
  list=$(_tui_list)
  cur=$(_tui_current)
  if [[ -n "$cur" ]]; then
    # Exact field-1 match, not a substring: grep -F "nix-config:1" would also
    # hit a worktree row like "other/nix-config:1".
    pos=$(printf '%s\n' "$list" | awk -F'\t' -v c="$cur" '$1 == c { print NR; exit }')
    : "${pos:=1}"
  fi

  # switch-client must name the caller's client: inside display-popup an
  # unscoped tmux command targets the popup's own client instead.
  local switch="tmux switch-client -t {1}"
  if [[ -n "${TMUX_OPENCODE_CALLER_TTY:-}" ]]; then
    switch="tmux switch-client -c ${TMUX_OPENCODE_CALLER_TTY} -t {1}"
  fi

  local reload="reload($self tui --list)"

  # Menu mode by default (--disabled): printable keys are shortcuts, not a
  # filter. "/" switches to live search, Esc returns to menu mode (detected via
  # $FZF_PROMPT). transform~...~ uses ~ as delimiter because the action bodies
  # contain ()/[] the default parser would choke on.
  local b_enter="become($self notify dismiss-target {1} >/dev/null 2>&1; $switch)"
  local b_dismiss="execute-silent($self notify dismiss-target {1})+$reload"
  local b_dismiss_all="execute-silent($self notify dismiss all; tmux refresh-client -S)+$reload"
  # The trailing reload runs after change-prompt, so the child sees
  # FZF_PROMPT="/ " and spells out every session name for the search.
  local b_search="unbind(d)+unbind(D)+unbind(j)+unbind(k)+unbind(q)+unbind(/)+clear-query+change-prompt(/ )+enable-search+$reload"
  local b_esc_back="clear-query+disable-search+change-prompt(❯ )+rebind(d)+rebind(D)+rebind(j)+rebind(k)+rebind(q)+rebind(/)+$reload"
  # shellcheck disable=SC2016 # $FZF_PROMPT is fzf's, not this shell's
  local b_esc='transform~[ "$FZF_PROMPT" = "/ " ] && echo "'"$b_esc_back"'" || echo abort~'

  # --sync: load all input before `start` fires, so start:pos() actually lands
  # on the current pane. The list is already in memory, so EOF is immediate.
  # load:reload(sleep 2; ...) is fzf's auto-refresh idiom — reload re-fires
  # `load`, so the list self-refreshes on a 2s beat. It also means a reader is
  # always in flight, which is why --info=hidden: the alternative is a spinner
  # that never stops turning.
  # ponytail: replaces the old fswatch watcher + USR1 trap + manual scroll
  # bookkeeping. Poll cadence matches the old read -t 2 loop.
  local rc=0
  printf '%s\n' "$list" | fzf \
    --ansi --no-sort --layout=reverse --cycle \
    --delimiter='\t' --with-nth=2 \
    --disabled --sync \
    --prompt='❯ ' \
    --info=hidden \
    --pointer='▶' \
    --gutter=' ' \
    --color='pointer:green,prompt:green,info:dim,header:dim' \
    --header='enter goto · d dismiss · D all · / search' \
    --bind "start:pos($pos)" \
    --bind "load:reload(sleep 2; $self tui --list)" \
    --bind "enter:$b_enter" \
    --bind 'j:down' \
    --bind 'k:up' \
    --bind "d:$b_dismiss" \
    --bind "D:$b_dismiss_all" \
    --bind 'q:abort' \
    --bind "/:$b_search" \
    --bind "esc:$b_esc" || rc=$?

  # Closing the picker is not a failure. fzf exits 130 on abort (q/Esc) and 1
  # on "nothing selected"; the tmux bind wraps this in run-shell, which reports
  # any non-zero status to the user as `... returned 130`.
  if [[ $rc -eq 1 || $rc -eq 130 ]]; then
    rc=0
  fi
  return $rc
}

eval "$(argc --argc-eval "$0" "$@")"
