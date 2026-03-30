#!/usr/bin/env bash

# tmux-opencode-generating: Outputs JSON array of sessions actively generating.
# Queries the opencode SQLite DB for assistant messages with time.completed = NULL,
# then cross-references with tmux panes running opencode.

set -u

OPENCODE_DB="${HOME}/.local/share/opencode/opencode-local.db"

if [[ ! -f "$OPENCODE_DB" ]] || ! command -v sqlite3 &>/dev/null || ! command -v tmux &>/dev/null; then
  echo '[]'
  exit 0
fi

panes=$(tmux list-panes -a -F '#{session_name} #{window_index} #{pane_current_command} #{pane_current_path}' 2>/dev/null | \
  awk '/opencode/ {print $1, $2, $4}' | sort -u)

if [[ -z "$panes" ]]; then
  echo '[]'
  exit 0
fi

# Directories with an assistant message still streaming (time.completed is null).
# Capped at 2 hours to skip stale entries from crashed sessions.
query="SELECT DISTINCT s.directory FROM message m
  JOIN session s ON m.session_id = s.id
  WHERE json_extract(m.data, '\$.role') = 'assistant'
    AND (json_extract(m.data, '\$.time.completed') IS NULL
         OR json_extract(m.data, '\$.time.completed') = '')
    AND m.time_created > ((strftime('%s', 'now') - 7200) * 1000)"

gen_dirs=$(sqlite3 "$OPENCODE_DB" "$query" 2>/dev/null)

if [[ -z "$gen_dirs" ]]; then
  echo '[]'
  exit 0
fi

matched=""
while IFS=' ' read -r sess win path; do
  if echo "$gen_dirs" | grep -qxF "$path"; then
    matched+="${sess} ${win}"$'\n'
  fi
done <<< "$panes"

if [[ -z "${matched:-}" ]]; then
  echo '[]'
  exit 0
fi

echo "$matched" | awk 'NF {printf "%s %s\n", $1, $2}' | \
  jq -Rn '[inputs | split(" ") | {session: .[0], target: (.[0] + ":" + .[1])}]'
