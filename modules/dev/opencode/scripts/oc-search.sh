#!/usr/bin/env bash

# Search opencode session history from a tmux popup (prefix+n).
#
# Two searches, deliberately kept apart:
#   typing  fzf's own fuzzy match over the visible "time · dir · title" row.
#           Client-side, instant, never touches the DB.
#   ^g      SQL grep over message *bodies* — the thing fzf cannot see.
#
# Scope (tab cycles active → 30d → all) is a relevance filter, not a speed
# one. Measured on a 6.7GB / 1581-root-session db, a body grep for "worktree"
# costs 0.02s/0.47s/0.57s across the three scopes but matches 7/240/1006
# sessions. Widening is cheap; reading 1006 hits is not. So: start narrow,
# tab to widen when you miss.
#
# The 0.57s "all" figure depends entirely on the EXISTS form below. Filtering
# on part's own columns instead (`WHERE part.time_created > ...`) full-scans
# every row and costs 6-8s, because `part` is indexed by session_id and
# nothing else. Narrow on `session` first, always.

DB="file:$HOME/.local/share/opencode/opencode.db?mode=ro"

# Popup state, reset on every open. Two files rather than one parsed blob so
# tab can re-run the *current* grep against the next scope without the script
# ever interpolating a user string into an fzf action body.
SCOPE_F="${TMPDIR:-/tmp}/oc-search.scope"
QUERY_F="${TMPDIR:-/tmp}/oc-search.query"

TAB=$'\t'
DIM=$'\033[2m'
RST=$'\033[0m'
GRN=$'\033[32m'
YEL=$'\033[33m'

self="$0"

# Session ids currently live in a tmux pane. The opencode-manager plugin
# stamps @oc-sid on every pane running a TUI, so "active" costs no query at
# all — it is read straight off the tmux server.
active_ids() {
  tmux list-panes -a -F '#{@oc-sid}' 2>/dev/null | grep -v '^$' | sort -u || true
}

# tmux session whose working dir is $1, empty if none. Matching on
# session_path rather than deriving a name from the path, because the two
# disagree: monobloco's main checkout lives in a session called "telepatia".
# Only tmux knows the real mapping.
sess_for() {
  tmux list-sessions -F "#{session_path}${TAB}#{session_name}" 2>/dev/null |
    awk -F'\t' -v d="$1" '$1 == d {print $2; exit}' || true
}

# scope name → SQL predicate over `session s`
scope_pred() {
  case "$1" in
  active)
    local ids
    ids=$(active_ids | sed "s/.*/'&'/" | paste -sd, - || true)
    # No live panes → match nothing, rather than silently falling back to
    # every session (which would look like the scope quietly broke).
    if [ -z "$ids" ]; then echo "0=1"; else echo "s.id IN ($ids)"; fi
    ;;
  30d) echo "s.time_updated > strftime('%s','now','-30 days')*1000" ;;
  *) echo "1=1" ;;
  esac
}

next_scope() {
  case "$1" in
  active) echo "30d" ;;
  30d) echo "all" ;;
  *) echo "active" ;;
  esac
}

read_scope() { cat "$SCOPE_F" 2>/dev/null || echo active; }
read_query() { cat "$QUERY_F" 2>/dev/null || true; }

# One row per session: "<id>\t<directory>\t<display>".
# fzf matches against the display field only (--with-nth=3), so an id or an
# absolute path can never accidentally satisfy a fuzzy query.
build_list() {
  local scope="$1" query="$2" pred grep_pred esc
  pred=$(scope_pred "$scope")

  grep_pred=""
  if [ -n "$query" ]; then
    # SQL string escape. Without this a query containing an apostrophe
    # ("don't") terminates the literal and the statement fails.
    esc=${query//\'/\'\'}
    # text+reasoning only. The other 80% of parts are tool calls and step
    # markers, whose data is machine JSON — matching them turns a search for
    # "zentria" into every session that merely *listed a file* containing it,
    # and yields a snippet of raw tool envelope that reads as noise.
    grep_pred="AND EXISTS (SELECT 1 FROM part p
                           WHERE p.session_id = s.id
                             AND json_extract(p.data,'\$.type') IN ('text','reasoning')
                             AND p.data LIKE '%$esc%')"
  fi

  # Subagent sessions (parent_id NOT NULL) are 64% of all rows and are never
  # something you resume by hand, so they are excluded outright.
  # project_id 'global' is opencode's bucket for runs outside a repo, which is
  # where headless one-shots (lin ai) are parked on purpose. Also never resumed.
  local rows
  rows=$(sqlite3 -separator "$TAB" "$DB" "
    SELECT s.id,
           s.directory,
           strftime('%m-%d %H:%M', s.time_updated/1000, 'unixepoch', 'localtime'),
           replace(s.directory, '$HOME', '~'),
           s.title
    FROM session s
    WHERE s.parent_id IS NULL AND s.time_archived IS NULL
      AND s.project_id <> 'global' AND $pred $grep_pred
    ORDER BY s.time_updated DESC" 2>/dev/null) || true
  [ -z "$rows" ] && return 0

  local -A LIVE=()
  local sid
  while IFS= read -r sid; do
    [ -n "$sid" ] && LIVE["$sid"]=1
  done < <(active_ids)

  local id dir when short title mark
  while IFS="$TAB" read -r id dir when short title; do
    [ -z "$id" ] && continue
    # ● marks a session with a TUI already open; enter jumps to that pane
    # instead of starting a second one on the same session.
    if [ -n "${LIVE[$id]:-}" ]; then mark="${GRN}●${RST}"; else mark=" "; fi
    printf '%s\t%s\t%s %s%s%s  %s%-38.38s%s  %s\n' \
      "$id" "$dir" "$mark" "$DIM" "$when" "$RST" "$DIM" "$short" "$RST" "$title"
  done <<<"$rows"
}

# Preview rows arrive stamped ␟<role>␟ by SQL; turn that into a coloured
# gutter bar on *every* line, plus a label wherever the speaker changes.
#
# The wrapping is ours rather than fzf's. fzf draws continuation lines knowing
# nothing about the gutter, so a wrapped paragraph lost its bar halfway down and
# read as though the speaker had changed mid-sentence. Wrapping here means every
# physical line carries the bar. FZF_PREVIEW_COLUMNS is what fzf exports for
# exactly this; fzf's own wrap stays on as the backstop for a single word too
# long to break (a URL, a base64 blob).
#
# The stamp is a printable glyph rather than a control byte because sqlite's CLI
# renders char(1) as the two literal characters "^A" — a \001 sentinel never
# survives the pipe, and "^A" itself turns up in these transcripts for real.
role_lines() {
  awk -v s="␟" -v w="$((${FZF_PREVIEW_COLUMNS:-80} - 2))" -v r="${RST}" \
    -v u="${YEL}▌${RST} " -v a="${DIM}│${RST} " -v y="${DIM}┊${RST} " \
    -v ul="${YEL}▌ you${RST}" -v al="${DIM}│ opencode${RST}" -v yl="${DIM}┊ system${RST}" '
    # Columns actually occupied: grep --color has already injected escapes by
    # this point and they take up no width. The class is [A-Za-z], not just m,
    # because GNU grep also emits \033[K after every colour change.
    function strip(t) { gsub(/\033\[[0-9;]*[A-Za-z]/, "", t); return t }
    function vlen(t) { return length(strip(t)) }
    function emit(line, pfx,   ind, out, n, i, arr) {
      if (vlen(line) <= w) { print pfx line r; return }
      match(line, /^[ \t]*/)
      ind = substr(line, 1, RLENGTH)
      n = split(substr(line, RLENGTH + 1), arr, " ")
      out = ind
      for (i = 1; i <= n; i++) {
        if (out == ind) out = out arr[i]
        else if (vlen(out) + 1 + vlen(arr[i]) <= w) out = out " " arr[i]
        else { print pfx out r; out = ind arr[i] }
      }
      print pfx out r
    }
    {
      # grep -C1 group separator: a blank line reads better than "--", and
      # clearing the speaker makes the next block re-announce itself.
      if (strip($0) == "--") { print ""; last = ""; next }

      slen = length(s)
      if (substr($0, 1, slen) == s) {
        rest = substr($0, slen + 1)
        i = index(rest, s)
        role = substr(rest, 1, i - 1)
        $0 = substr(rest, i + slen)
        if (role != last) {
          if (last != "") print ""
          print (role == "user") ? ul : (role == "system") ? yl : al
          last = role
        }
        pfx = (role == "user") ? u : (role == "system") ? y : a
      }
      emit($0, pfx)
    }'
}

header_for() {
  local scope="$1" q label
  q=$(read_query)
  label="$scope"
  if [ -n "$q" ]; then
    # This string is emitted inside a change-header(...) fzf action, whose body
    # ends at the matching paren — a query containing one would truncate the
    # header and feed fzf the remainder as bogus actions. Stripped here rather
    # than escaped because the label is a hint; the grep itself still uses the
    # untouched query.
    q=${q//[()]/}
    [ ${#q} -gt 24 ] && q="${q:0:24}…"
    label="$scope ${YEL}· grep '$q'${RST}"
  fi
  printf 'scope: %s%s%s   tab widen · ^g grep bodies · ^p preview · enter open' "$GRN" "$label" "$RST"
}

case "${1:-}" in
--list)
  build_list "$(read_scope)" "$(read_query)"
  exit 0
  ;;

# Advance the scope and re-run whatever grep is active. Emitted as fzf actions
# by a transform bind, so tab never has to interpolate the query itself.
--cycle)
  new=$(next_scope "$(read_scope)")
  printf '%s' "$new" >"$SCOPE_F"
  printf 'reload(%s --list)+change-header(%s)' "$self" "$(header_for "$new")"
  exit 0
  ;;

# Body grep. clear-query is not cosmetic: after grepping, fzf's own filter
# would keep matching the typed term against *titles* and hide the body-only
# hits the grep just found — the exact results you asked for.
--grep)
  printf '%s' "${2:-}" >"$QUERY_F"
  printf 'reload(%s --list)+clear-query+change-header(%s)' "$self" "$(header_for "$(read_scope)")"
  exit 0
  ;;

# The point of a body grep is seeing what was said, not a list of titles that
# each merely contain the word somewhere. Prints the matching lines with a line
# of context, highlighted, from the same text+reasoning parts the list query
# used — so the preview can never show a hit the list disagrees with.
--preview)
  sid="${2:-}"
  [ -z "$sid" ] && exit 0
  sesc=${sid//\'/\'\'}
  pq=$(read_query)
  # Harness-injected turns are stored with role=user, so a naive label credits
  # background-task notices and todo nags to "you" — the exact confusion the
  # gutter is there to remove. The synthetic flag catches a third of them, the
  # literal opener catches the rest.
  # `IS`/coalesce, not `=`: an absent synthetic key yields NULL, and `NOT NULL`
  # is NULL, so the plain form filtered out every row and blanked the pane.
  noise="(json_extract(p.data,'\$.synthetic') IS 1
          OR coalesce(json_extract(p.data,'\$.text'), '') LIKE '<system-reminder>%')"
  rolesql="CASE WHEN json_extract(m.data,'\$.role') = 'user' AND $noise
                THEN 'system' ELSE json_extract(m.data,'\$.role') END"
  sel="SELECT '␟' || $rolesql || '␟' || coalesce(json_extract(p.data,'\$.text'), '')
       FROM part p JOIN message m ON m.id = p.message_id"
  if [ -n "$pq" ]; then
    qesc=${pq//\'/\'\'}
    sqlite3 "$DB" "$sel
                   WHERE p.session_id = '$sesc'
                     AND json_extract(p.data,'\$.type') IN ('text','reasoning')
                     AND p.data LIKE '%$qesc%'
                   ORDER BY p.time_created LIMIT 40" 2>/dev/null |
      grep -i -F --color=always -C1 -- "$pq" 2>/dev/null |
      role_lines | head -200 || true
  else
    # No grep active: the opening exchange is the cheapest answer to "what was
    # this session even about", which the title often does not settle. Harness
    # turns are dropped from *this* view only — a background-task notice answers
    # nothing and runs long enough to eat the whole 8-part budget on its own.
    # The grep branch keeps them: there you asked for a literal string, and a
    # view that hides matching hits is worse than a noisy one.
    sqlite3 "$DB" "$sel
                   WHERE p.session_id = '$sesc'
                     AND json_extract(p.data,'\$.type') = 'text'
                     AND NOT $noise
                   ORDER BY p.time_created LIMIT 8" 2>/dev/null |
      role_lines | head -200 || true
  fi
  exit 0
  ;;

--open)
  sid="${2:-}"
  dir="${3:-}"
  [ -z "$sid" ] && exit 0
  # Already running somewhere → go to it. Launching a second TUI on a live
  # session gives two clients fighting over the same history.
  target=$(tmux list-panes -a \
    -F "#{session_name}${TAB}#{window_id}${TAB}#{pane_id}${TAB}#{@oc-sid}" 2>/dev/null |
    awk -F'\t' -v s="$sid" '$4 == s {print $1 "\t" $2 "\t" $3; exit}') || true
  if [ -n "$target" ]; then
    IFS="$TAB" read -r tsess twin tpane <<<"$target"
    tmux switch-client -t "=$tsess"
    tmux select-window -t "$twin"
    tmux select-pane -t "$tpane"
  else
    # 43% of recorded directories are deleted worktrees. `new-window -c` on a
    # missing dir does not fail — tmux silently falls back to $HOME and exits
    # 0 — so the session would resume against the wrong tree with no warning.
    # Resolve to the worktree's main checkout instead (same naming convention
    # wtoc uses); it still holds the branch the work landed on.
    if [ -n "$dir" ] && [ ! -d "$dir" ]; then
      root=${dir%%.worktrees/*}
      if [ "$root" != "$dir" ] && [ -d "$root" ]; then dir="$root"; else dir="$HOME"; fi
    fi
    # File the window under the session that owns $dir, not under whichever
    # session you happened to press prefix+n in — a cross-repo hit landing in
    # the wrong window list is a thing you then have to go find again.
    sess=$(sess_for "$dir")
    if [ -n "$sess" ]; then
      tmux new-window -t "=$sess" -c "$dir" "opencode --session $sid"
    elif [ "$dir" = "$HOME" ]; then
      # The give-up path above: no repo left, so no session worth inventing.
      tmux new-window -c "$dir" "opencode --session $sid"
      exit 0
    else
      # Nothing open for it yet. Name it the way wt does — "<parent>/<worktree>"
      # under .worktrees, bare "<repo>" otherwise — so this is the session wt
      # would later reuse, not a duplicate sitting beside it.
      # -P -F echoes the name tmux actually used, which differs from the one
      # asked for when it holds a "." or ":" (both are rewritten to "_").
      root=${dir%%.worktrees/*}
      sess=$(basename "$dir")
      if [ "$root" != "$dir" ]; then
        parent=$(sess_for "$root")
        sess="${parent:-$(basename "$root")}/$sess"
      fi
      sess=$(tmux new-session -d -P -F '#{session_name}' \
        -s "$sess" -c "$dir" "opencode --session $sid")
    fi
    tmux switch-client -t "=$sess"
  fi
  exit 0
  ;;
esac

# Fresh popup: always start narrow and ungrepped.
printf 'active' >"$SCOPE_F"
: >"$QUERY_F"

list=$(build_list active "")
[ -z "$list" ] && list=$(printf '\t\t%sno active opencode sessions — tab to widen%s' "$DIM" "$RST")

# Unlike the tmux session picker this is NOT --disabled: you open it to search,
# so typing filters immediately. tab/^g are non-printable and cannot collide.
printf '%s\n' "$list" | fzf \
  --ansi --no-sort --layout=reverse --cycle \
  --delimiter='\t' --with-nth=3 \
  --prompt='❯ ' \
  --info=inline-right \
  --pointer='▶' \
  --gutter=' ' \
  --color='pointer:green,prompt:green,info:dim,header:dim' \
  --header="$(header_for active)" \
  --preview "$self --preview {1}" \
  --preview-window 'right:52%:wrap:border-left' \
  --preview-wrap-sign '  ' \
  --bind 'ctrl-p:toggle-preview' \
  --bind "tab:transform:$self --cycle" \
  --bind "ctrl-g:transform:$self --grep {q}" \
  --bind "enter:become($self --open {1} {2})" \
  --bind 'ctrl-c:abort' \
  --bind 'esc:abort'
