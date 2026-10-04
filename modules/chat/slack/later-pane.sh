#!/usr/bin/env bash
# Read-only Slack Later picker for a tmux popup (prefix+L), the same overlay
# shape as the session picker. Strictly a viewer: it reads the backend's
# `tmux-slack-later-list` JSON and opens a row. Nothing here completes, snoozes
# or mutates a saved item, so the popup cannot damage the list it shows.
set -uo pipefail

WORKSPACE=${TMUX_SLACK_LATER_WORKSPACE:-}
# umask 077 in a per-user TMPDIR: the snapshot is real Later content, so it
# never lands in a shared path or a repo fixture.
SNAP="${TMPDIR:-/tmp}/tmux-slack-later-pane.json"
# Set once the pane's first real backend load has been kicked off, so the `load`
# event can tell that one from every later one without fzf keeping state for us.
LOADED="$SNAP.loaded"
# Set once that load has delivered. Until then a reload would kill it mid-fetch,
# so tab clears LOADED instead and the reload's own load event fetches again.
FETCHED="$SNAP.fetched"
# flat | channel, flipped by tab. A file because every bind is its own process;
# reset to the configured default on each open, like the session picker's view.
MODE="$SNAP.mode"
DEFAULT_GROUP=${TMUX_SLACK_LATER_GROUP:-channel}

mode() {
  case "$(cat "$MODE" 2>/dev/null)" in
    flat) echo flat ;;
    channel) echo channel ;;
    *) echo "$DEFAULT_GROUP" ;;
  esac
}
# fzf runs every bind through `sh -c`, so the re-entry command has to be one a
# shell can actually execute. $0 alone is not: this file lives in the nix store
# with no executable bit, and the wrapper reaches it as an argument to bash.
# Naming that bash explicitly also skips a PATH lookup for our own name.
self="${BASH:-bash} \"$0\""

# One list call per view change, not per subcommand: --list and --header run off
# the same snapshot, so the header cannot claim a count the rows disagree with.
# Args are forwarded: `snapshot --cached` takes whatever the backend already has
# without waiting for a fetch.
snapshot() {
  local tmp
  umask 077
  tmp=$(mktemp "$SNAP.XXXXXX") || return 1
  # fzf kills a reader it has superseded, and this one is holding real Later
  # content in a half-written file.
  # shellcheck disable=SC2064  # expanding now is the point: $tmp is local
  trap "rm -f '$tmp'" EXIT HUP INT TERM
  if tmux-slack-later-list "$@" >"$tmp" 2>/dev/null &&
    jq -e 'type == "object"' "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$SNAP"
  else
    rm -f "$tmp"
    printf '{"counts":{},"items":[],"error":"unavailable","truncated":false}' >"$SNAP"
  fi
}

# Emits "<url>\t<display>"; fzf shows field 2 and the binds consume {1}. clean
# strips C0 and DEL first: titles are attacker-controlled (anyone who can DM you
# can put an ESC in one) and this pane is the only thing between a Slack message
# and the terminal's escape parser. Our dim/red codes are added after, so they
# are the only escapes that reach the screen.
#
# By channel, rows are regrouped in order of each conversation's first (newest)
# save, and the conversation's name leads the first row of its group only — a
# dim column, not a separator line, so every line stays a row enter can open.
render() {
  jq -r --arg mode "$(mode)" '
    def clean: tostring | gsub("[\u0000-\u001f\u007f]"; " ") | gsub(" {2,}"; " ") | ltrimstr(" ");
    def dim: "\u001b[2m" + . + "\u001b[0m";
    def red: "\u001b[31m" + . + "\u001b[0m";
    def pad($w): (.[0:$w]) | ($w - length) as $p | if $p > 0 then . + (" " * $p) else . end;
    def epoch:
      if type == "number" then .
      elif type == "string" and test("^[0-9]+(\\.[0-9]+)?$") then tonumber
      else (. as $v | try ($v | fromdateiso8601) catch null)
      end;
    def where:
      if (.channel_name // "") != "" then .channel_name
      elif (.channel // "") != "" then .channel
      else "?" end
      | clean;
    def row($prefix):
      ((.date_due | epoch) as $d | $d != null and $d > 0 and $d < now) as $overdue
      | [ (.url // "" | tostring),
          ( $prefix
            + (if $overdue then ("! " | red) else "" end)
            + ((.title // "") | clean | if length == 0 then ("untitled" | dim) else . end) )
        ];

    (.items // [])
    | if type == "array" then map(select(type == "object")) else [] end
    | if $mode == "channel" then
        reduce .[] as $i ([];
          ($i | where) as $w
          | (map(.name) | index($w)) as $at
          | if $at == null then . + [{ name: $w, items: [$i] }]
            else .[$at].items += [$i] end)
        | ([.[].name | length] | max // 0 | if . > 24 then 24 else . end) as $w
        | .[]
        | .name as $name
        | .items | to_entries[]
        | (.key == 0) as $first
        | .value | row((if $first then $name else "" end | pad($w) | dim) + "  ")
      else
        .[] | row("")
      end
    | @tsv
  ' "$SNAP" 2>/dev/null
}

# Says which nothing this is — an empty list and a failed read look identical
# otherwise. Field 1 is empty, so enter on a placeholder is a no-op.
placeholder() {
  local error
  error=$(jq -r '(.error // "") | tostring | gsub("[^a-zA-Z0-9 _-]"; "")' "$SNAP" 2>/dev/null) || error=""
  case "$error" in
    "") printf '\033[2mnothing saved for later\033[0m' ;;
    loading) printf '\033[2mloading Later…\033[0m' ;;
    *) printf '\033[2mcould not load Later (%s) — r to retry\033[0m' "$error" ;;
  esac
}

# "Later · 12 · 10 shown · truncated · ⚠ credentials". The tally shows only when
# it disagrees with the count and the warning only when there is one: a header
# that is always full is a header nobody reads.
header_line() {
  local n shown truncated error extra=""
  # Tab is IFS whitespace, so `read` collapses a run of them: an empty field in
  # the middle would shift every field after it left, and the error would
  # silently arrive in `truncated`. Only the last field is allowed to be empty.
  IFS=$'\t' read -r n shown truncated error <<<"$(jq -r '
    [ (.counts.uncompleted_count // 0),
      ((.items // []) | if type == "array" then length else 0 end),
      (if .truncated == true then "1" else "0" end),
      ((.error // "") | tostring | gsub("[^a-zA-Z0-9 _-]"; "")) ]
    | @tsv
  ' "$SNAP" 2>/dev/null)"
  case "${n:-}" in "" | *[!0-9]*) n=0 ;; esac
  case "${shown:-}" in "" | *[!0-9]*) shown=0 ;; esac
  [ "$shown" = "$n" ] || extra=" · $shown shown"
  [ "${truncated:-0}" != 1 ] || extra="$extra · truncated"
  # A fetch in flight is not a failure: no ⚠, just a count that is not final.
  case "${error:-}" in
    "") ;;
    loading) extra="$extra · loading…" ;;
    *) extra="$extra · ⚠ $error" ;;
  esac
  # Set by r for as long as its refresh runs; the load that ends it redraws the
  # header without it.
  [ "${1:-}" != refreshing ] || extra="$extra · refreshing…"
  # The key line doubles as the view indicator, the session picker's way: the
  # prompt cannot, "/" search already uses it as its sentinel.
  printf 'Later · %s%s\n' "$n" "$extra"
  if [ "$(mode)" = channel ]; then
    printf 'enter open · / search · r refresh · tab flat · q quit\n'
  else
    printf 'enter open · / search · r refresh · tab by channel · q quit\n'
  fi
}

# Only the exact configured workspace host, or Slack's own app scheme. The
# leading-anchored patterns make "https://evil.test@workspace/..." fail, and an
# unset workspace fails closed rather than trusting every https url.
valid_url() {
  case "$1" in
    *[[:cntrl:][:space:]]* | "") return 1 ;;
  esac
  [ -n "$WORKSPACE" ] || case "$1" in slack://*) return 0 ;; *) return 1 ;; esac
  case "$1" in
    "https://$WORKSPACE" | "https://$WORKSPACE/"* | slack://*) return 0 ;;
    *) return 1 ;;
  esac
}

case "${1:-}" in
  # --load is --list with the real backend call in front of it: the fetch fzf
  # runs behind the cached rows once they are already on screen.
  # --refresh is --load with a forced backend refresh in front, run by r the same
  # way: under reload-sync, behind rows that stay up and usable. FETCHED comes off
  # for the duration, so a tab that kills this mid-fetch re-arms a load instead.
  --list | --load | --refresh)
    if [ "$1" = --refresh ]; then
      rm -f "$FETCHED"
      tmux-slack-later-refresh >/dev/null 2>&1 || true
    fi
    [ "$1" = --list ] || { snapshot && : 2>/dev/null >"$FETCHED"; }
    rows=$(render)
    [ -n "$rows" ] || rows=$'\t'"$(placeholder)"
    printf '%s\n' "$rows"
    exit 0
    ;;
  --header)
    header_line "${2:-}"
    exit 0
    ;;
  # fzf fires `load` after every list it finishes reading. The first one is the
  # cached snapshot, and answers with the fetch that replaces it; every later
  # one is a finished fetch, and answers with the header it left behind. Both
  # are printed for fzf's `transform`, which runs whatever actions it is given.
  --loaded)
    # A marker we cannot write answers as if the fetch already happened: fzf
    # loads what a reload delivers, so a reload it can never mark down is a loop.
    if [ -e "$LOADED" ] || ! : 2>/dev/null >"$LOADED"; then
      printf 'transform-header(%s --header)' "$self"
    else
      printf 'reload-sync(%s --load)' "$self"
    fi
    exit 0
    ;;
  # Bound to tab, in menu and search mode alike (it types nothing). Answers with
  # the actions that repaint from the snapshot already on disk — no fetch.
  --toggle)
    if [ "$(mode)" = channel ]; then
      printf 'flat\n' >"$MODE" 2>/dev/null || true
    else
      printf 'channel\n' >"$MODE" 2>/dev/null || true
    fi
    [ -e "$FETCHED" ] || rm -f "$LOADED"
    printf 'reload(%s --list)+transform-header(%s --header)' "$self" "$self"
    exit 0
    ;;
  --open)
    valid_url "${2:-}" || exit 0
    open "$2" >/dev/null 2>&1 || true
    exit 0
    ;;
esac

# Whatever the backend already has, with no fetch in the way: a cache that is
# stale, or missing entirely, still gives fzf something to be interactive with
# on the first frame. The fetch happens under the `load` bind below.
rm -f "$LOADED" "$FETCHED" "$MODE"
snapshot --cached
list=$(render)
[ -n "$list" ] || list=$'\t'"$(placeholder)"

# shellcheck disable=SC2016  # {1} is fzf's placeholder (shell-quoted by fzf)
b_open='execute-silent('"$self"' --open {1})'
# Not execute-silent: that blocks fzf for the whole refresh, which pages through
# Slack and takes seconds. The header says it is running; the load event that
# follows the reload puts the plain header back.
b_refresh='transform-header('"$self"' --header refreshing)+reload-sync('"$self"' --refresh)'
# Menu mode by default, `/` for search — the PR popup's two modes. With search
# live from the start, q and r are letters you could not type, so they come off
# for the duration of a query; change:clear-query wipes the letters --disabled
# would otherwise silently collect in menu mode.
b_search='unbind(change)+unbind(q)+unbind(r)+unbind(/)+clear-query+change-prompt(/ )+enable-search'
b_esc_back='clear-query+disable-search+change-prompt(❯ )+rebind(change)+rebind(q)+rebind(r)+rebind(/)'
# shellcheck disable=SC2016  # $FZF_PROMPT is fzf's variable, not bash's
b_esc='transform~[ "$FZF_PROMPT" = "/ " ] && echo "'"$b_esc_back"'" || echo abort~'
# search() re-matches every row, which a cleared query no longer does once
# search is off, and it has to ride on the bind: emitted from the transform,
# fzf ignores it. It stands in for the reload that used to end this path, which
# killed the first load still fetching — with the marker down, nothing would
# start another. On the abort branch fzf is quitting, so it lands nowhere.
b_esc="$b_esc+search()"

printf '%s\n' "$list" | fzf \
  --ansi --no-sort --layout=reverse --cycle \
  --delimiter='\t' --with-nth=2 \
  --disabled \
  --prompt='❯ ' \
  --info=inline-right \
  --pointer='▶' \
  --gutter=' ' \
  --color='pointer:green,prompt:green,info:dim,header:dim' \
  --header="$(header_line)" \
  --bind "load:transform($self --loaded)" \
  --bind "tab:transform($self --toggle)" \
  --bind "enter:$b_open" \
  --bind "r:$b_refresh" \
  --bind "/:$b_search" \
  --bind 'change:clear-query' \
  --bind 'q:abort' \
  --bind 'ctrl-c:abort' \
  --bind "esc:$b_esc"
