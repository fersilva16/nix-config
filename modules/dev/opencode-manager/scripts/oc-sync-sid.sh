#!/usr/bin/env bash

set -eu

PANE_ID="${1:?}"

STATUS=$(tmux show-options -pv -t "$PANE_ID" @oc-status 2>/dev/null || true)
[[ "$STATUS" != "active" ]] && exit 0

DIR=$(tmux show-options -pv -t "$PANE_ID" @oc-dir 2>/dev/null || true)
[[ -z "$DIR" ]] && exit 0

TITLE=$(tmux display-message -p -t "$PANE_ID" '#{pane_title}' 2>/dev/null || true)
[[ "$TITLE" != OC\ \|\ * ]] && exit 0

EXTRACTED="${TITLE#OC | }"

DB="$HOME/.local/share/opencode/opencode-local.db"
[[ ! -f "$DB" ]] && exit 0

SAFE=$(printf '%s' "$EXTRACTED" | sed "s/'/''/g")

if printf '%s' "$EXTRACTED" | grep -q '\.\.\.$'; then
  # Truncated title — prefix match, multiple candidates possible.
  # Prefer session not already claimed by another pane to disambiguate
  # forks from originals (e.g. "Long title..." matches both
  # "Long title" and "Long title (fork #1)").
  SAFE=$(printf '%s' "$SAFE" | sed 's/\.\.\.$//')
  CANDIDATES=$(sqlite3 "$DB" \
    "SELECT id FROM session WHERE directory='$DIR' AND title LIKE '$SAFE%'
     ORDER BY time_updated DESC" 2>/dev/null || true)
  [[ -z "$CANDIDATES" ]] && exit 0

  CLAIMED=$(tmux list-panes -a -F '#{pane_id}:#{@oc-sid}' 2>/dev/null |
    grep -v "^${PANE_ID}:" | cut -d: -f2 | sort -u)

  NEW_SID=""
  FALLBACK=""
  while IFS= read -r cid; do
    [[ -z "$cid" ]] && continue
    [[ -z "$FALLBACK" ]] && FALLBACK="$cid"
    if ! printf '%s\n' "$CLAIMED" | grep -qx "$cid"; then
      NEW_SID="$cid"
      break
    fi
  done <<<"$CANDIDATES"
  NEW_SID="${NEW_SID:-$FALLBACK}"
else
  NEW_SID=$(sqlite3 "$DB" \
    "SELECT id FROM session WHERE directory='$DIR' AND title = '$SAFE'
     ORDER BY time_updated DESC LIMIT 1" 2>/dev/null || true)
fi

[[ -z "$NEW_SID" ]] && exit 0

CURRENT=$(tmux show-options -pv -t "$PANE_ID" @oc-sid 2>/dev/null || true)
[[ "$NEW_SID" == "$CURRENT" ]] && exit 0

tmux set-option -p -t "$PANE_ID" @oc-sid "$NEW_SID" 2>/dev/null || true
