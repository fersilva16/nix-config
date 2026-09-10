#!/usr/bin/env bash
# Self-check for the Later pane's rendering and its url gate. Drives
# later-pane.sh directly with a fixture snapshot and fake list/refresh/open
# binaries on PATH, so it never opens Chrome, the keychain or the network.
#
# The url gate is the part worth pinning: every row here came from a Slack
# message somebody else wrote, so "enter opens the selected url" is a hostile
# input path. A regression that lets one extra url shape through still renders
# perfectly and errors nowhere.
#
# Run by hand: bash later-pane.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PANE="$HERE/later-pane.sh"
WORKSPACE=example.slack.com

[[ -f "$PANE" ]] || {
  echo "FAIL: $PANE not found"
  exit 1
}

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/bin"
OPENED="$SANDBOX/opened"
CALLED="$SANDBOX/called"

for fake in open tmux-slack-later-refresh tmux-slack-later-list; do
  printf '#!/bin/sh\nprintf "%%s\\n" "%s $*" >>"%s"\n' "$fake" "$CALLED" >"$SANDBOX/bin/$fake"
  chmod +x "$SANDBOX/bin/$fake"
done
# open is the one fake with its own log: the tests below assert on exactly
# which urls reached it, not merely that something ran.
cat >"$SANDBOX/bin/open" <<EOF
#!/bin/sh
printf '%s\n' "\$1" >>"$OPENED"
EOF
chmod +x "$SANDBOX/bin/open"
# The list fake must emit valid JSON or --refresh's snapshot falls back to its
# error shape, which would make the refresh assertion pass for the wrong reason.
cat >"$SANDBOX/bin/tmux-slack-later-list" <<EOF
#!/bin/sh
printf '%s\n' "tmux-slack-later-list" >>"$CALLED"
printf '{"counts":{"uncompleted_count":1},"items":[{"id":"x","title":"fresh","url":""}],"error":"","truncated":false}'
EOF
chmod +x "$SANDBOX/bin/tmux-slack-later-list"

fail=0
snapshot() { printf '%s' "$1" >"$SANDBOX/tmux-slack-later-pane.json"; }

run() {
  PATH="$SANDBOX/bin:$PATH" TMPDIR="$SANDBOX" TMUX_SLACK_LATER_WORKSPACE="$WORKSPACE" \
    bash "$PANE" "$@" 2>/dev/null
}

# Strips the pane's own SGR codes; only text, ordering and marks are asserted.
plain() { sed 's/\x1b\[[0-9;]*m//g'; }

check() {
  local label=$1 got=$2 want=$3
  if [[ "$got" == "$want" ]]; then
    printf 'ok: %s\n' "$label"
  else
    printf 'FAIL: %s\n  expected: %q\n  got:      %q\n' "$label" "$want" "$got"
    fail=1
  fi
}

now=$(date +%s)
past=$((now - 86400))
future=$((now + 86400))

full=$(
  cat <<EOF
{"counts":{"uncompleted_count":3,"uncompleted_overdue_count":1},
 "items":[
   {"id":"Sm001","title":"ship the migration","url":"https://$WORKSPACE/archives/C1/p1","date_created":$past,"date_due":$past},
   {"id":"Sm002","title":"read the RFC","url":"https://$WORKSPACE/archives/C1/p2","date_created":$past,"date_due":$future},
   {"id":"Sm003","title":"no due date","url":"https://$WORKSPACE/archives/C1/p3","date_created":$past,"date_due":null}],
 "error":"","truncated":false}
EOF
)

# ── header ────────────────────────────────────────────────────────────────
snapshot "$full"
check "header leads with the count" "$(run --header | head -1)" "Later · 3"
check "header advertises its keys" "$(run --header | sed -n 2p)" \
  "enter open · / search · r refresh · q quit"

snapshot '{"counts":{"uncompleted_count":9},"items":[{"id":"a","title":"t","url":""}],"error":"","truncated":true}'
check "a partial load says how much of it is on screen" "$(run --header | head -1)" \
  "Later · 9 · 1 shown · truncated"

snapshot '{"counts":{"uncompleted_count":2},"items":[{"id":"a","title":"t","url":""},{"id":"b","title":"u","url":""}],"error":"credentials","truncated":false}'
check "a stale read is admitted in the header" "$(run --header | head -1)" \
  "Later · 2 · ⚠ credentials"

# A malformed error must not become a second escape channel into the header.
snapshot '{"counts":{"uncompleted_count":0},"items":[],"error":"\u001b[31mfake\u0007","truncated":false}'
check "header error text is stripped to safe characters" "$(run --header | head -1)" \
  "Later · 0 · ⚠ 31mfake"

# ── rows ──────────────────────────────────────────────────────────────────
snapshot "$full"
check "rows show titles, never ids" "$(run --list | plain | cut -f2 | tr '\n' '|')" \
  "! ship the migration|read the RFC|no due date|"
check "row carries its url out of band for the binds" "$(run --list | head -1 | cut -f1)" \
  "https://$WORKSPACE/archives/C1/p1"
check "no opaque id reaches the screen" \
  "$(run --list | cut -f2 | grep -c 'Sm00')" "0"

# Anyone who can DM you can put an ESC in a title; this pane is the last thing
# before the terminal's escape parser.
snapshot "{\"counts\":{\"uncompleted_count\":1},\"items\":[{\"id\":\"x\",\"title\":\"pwn\u001b[31m\u0007\u001b]0;title\u0007ed\",\"url\":\"https://$WORKSPACE/a\"}],\"error\":\"\",\"truncated\":false}"
check "control characters never survive into a row" \
  "$(run --list | cut -f2 | grep -c $'\x1b\|\x07')" "0"
check "the sanitized title is still readable" "$(run --list | plain | cut -f2)" \
  "pwn [31m ]0;title ed"

# ── placeholders ──────────────────────────────────────────────────────────
snapshot '{"counts":{"uncompleted_count":0},"items":[],"error":"","truncated":false}'
check "an empty list says it is empty" "$(run --list | plain | cut -f2)" \
  "nothing saved for later"
check "the empty placeholder carries no url" "$(run --list | cut -f1)" ""

snapshot '{"counts":{"uncompleted_count":0},"items":[],"error":"loading","truncated":false}'
check "a first frame with no cache says so" "$(run --list | plain | cut -f2)" \
  "loading Later…"
check "a fetch in flight is not dressed as a failure" "$(run --header | head -1)" \
  "Later · 0 · loading…"

snapshot '{"counts":{"uncompleted_count":0},"items":[],"error":"credentials","truncated":false}'
check "a failed read does not pose as an empty list" "$(run --list | plain | cut -f2)" \
  "could not load Later (credentials) — r to retry"
check "the error placeholder carries no url" "$(run --list | cut -f1)" ""

# ── the url gate ──────────────────────────────────────────────────────────
: >"$OPENED"
for bad in \
  "" \
  "http://$WORKSPACE/a" \
  "https://evil.test/a" \
  "https://evil.test@$WORKSPACE/a" \
  "https://$WORKSPACE.evil.test/a" \
  "https://sub.$WORKSPACE/a" \
  "file:///etc/passwd" \
  "javascript:alert(1)" \
  "$WORKSPACE/a" \
  "https://$WORKSPACE/a b" \
  $'https://'"$WORKSPACE"$'/a\nhttps://evil.test'; do
  run --open "$bad"
done
check "every untrusted url shape is refused" "$(wc -l <"$OPENED" | tr -d ' ')" "0"

: >"$OPENED"
run --open "https://$WORKSPACE/archives/C1/p1"
run --open "https://$WORKSPACE"
run --open "slack://channel?team=T1&id=C1"
check "the configured workspace and slack:// still open" "$(wc -l <"$OPENED" | tr -d ' ')" "3"

# A placeholder row hands the bind an empty field 1, which must stay a no-op.
: >"$OPENED"
snapshot '{"counts":{"uncompleted_count":0},"items":[],"error":"","truncated":false}'
run --open "$(run --list | cut -f1)"
check "enter on a placeholder opens nothing" "$(wc -l <"$OPENED" | tr -d ' ')" "0"

# With no workspace configured the gate fails closed rather than trusting https.
: >"$OPENED"
PATH="$SANDBOX/bin:$PATH" TMPDIR="$SANDBOX" TMUX_SLACK_LATER_WORKSPACE="" \
  bash "$PANE" --open "https://$WORKSPACE/a" 2>/dev/null
check "an unconfigured workspace opens no https url" "$(wc -l <"$OPENED" | tr -d ' ')" "0"

# ── re-entry ──────────────────────────────────────────────────────────────
# Every bind re-invokes this script through fzf's `sh -c`. In the nix store the
# file has no executable bit and the wrapper reaches it as an argument to bash,
# so a bare $0 re-entry command fails — and only after a keypress, never on the
# first render, which is exactly the shape of bug a screenshot does not catch.
cat >"$SANDBOX/bin/fzf" <<EOF
#!/bin/sh
cat >/dev/null
printf '%s\n' "\$@" >"$SANDBOX/fzfargs"
EOF
chmod +x "$SANDBOX/bin/fzf"
chmod -x "$PANE" 2>/dev/null || true

run >/dev/null
reentry=$(sed -n 's/.*reload(\(.*\) --list).*/\1/p' "$SANDBOX/fzfargs" | head -1)
check "the binds re-enter through a runnable command" \
  "$([ -n "$reentry" ] && echo yes)" "yes"
check "that command works without an executable bit" \
  "$(PATH="$SANDBOX/bin:$PATH" TMPDIR="$SANDBOX" TMUX_SLACK_LATER_WORKSPACE="$WORKSPACE" \
    sh -c "$reentry --header" 2>/dev/null | head -1)" "Later · 1"
rm -f "$SANDBOX/bin/fzf"

# ── refresh ───────────────────────────────────────────────────────────────
: >"$CALLED"
run --refresh
check "r refreshes the backend cache before re-listing" \
  "$(grep -c 'tmux-slack-later-refresh' "$CALLED")" "1"
check "r then re-reads the list" \
  "$(grep -c 'tmux-slack-later-list' "$CALLED")" "1"
check "refresh leaves a usable snapshot" "$(run --header | head -1)" "Later · 1"

# ── the first frame ───────────────────────────────────────────────────────
# The backend's own list refreshes a stale cache before it answers, which is a
# network round trip the pane used to sit through with nothing on screen. So the
# pane must reach fzf off `--cached` alone and let fzf run the slow call behind
# the rows that are already up. This backend takes 3 seconds to answer anything
# but --cached, so a pane that still waits for it cannot pass on time.
cat >"$SANDBOX/bin/tmux-slack-later-list" <<EOF
#!/bin/sh
printf '%s\n' "list \$*" >>"$CALLED"
if [ "\$1" = --cached ]; then
  printf '{"counts":{"uncompleted_count":1},"items":[{"id":"c","title":"from cache","url":""}],"error":"","truncated":false}'
else
  sleep 3
  printf '{"counts":{"uncompleted_count":2},"items":[{"id":"f","title":"from Slack","url":""},{"id":"g","title":"also fresh","url":""}],"error":"","truncated":false}'
fi
EOF
chmod +x "$SANDBOX/bin/tmux-slack-later-list"
cat >"$SANDBOX/bin/fzf" <<EOF
#!/bin/sh
cat >"$SANDBOX/fzfstdin"
printf '%s\n' "\$@" >"$SANDBOX/fzfargs"
EOF
chmod +x "$SANDBOX/bin/fzf"

: >"$CALLED"
started=$(date +%s)
run >/dev/null
elapsed=$(($(date +%s) - started))
check "fzf starts before the slow backend answers" "$((elapsed < 3))" "1"
check "the first frame costs exactly one cached call" \
  "$(sort "$CALLED" | uniq -c | tr -s ' ' | sed 's/^ //')" "1 list --cached"
check "the rows fzf opens with are the cached ones" \
  "$(plain <"$SANDBOX/fzfstdin" | cut -f2)" "from cache"
check "the header fzf opens with matches them" \
  "$(grep -c '^--header=Later · 1$' "$SANDBOX/fzfargs")" "1"

# fzf re-asks on every load it finishes: the first answer fetches, the rest read
# back the header that fetch left behind. Without that turn the pane would loop
# reloading itself, and without the marker every reload would refetch.
loadbind=$(sed -n 's/^load:transform(\(.*\))$/\1/p' "$SANDBOX/fzfargs")
check "the load event is wired to the pane" \
  "$([ -n "$loadbind" ] && echo yes)" "yes"
# Restarting the reader kills whatever it is still reading, so a redraw on the
# way out of search would abort that first load and, with the marker already
# down, nothing would start another. Refresh may do it — the user asked.
check "leaving search does not abort the load" \
  "$(grep -c '^esc:.*reload' "$SANDBOX/fzfargs")" "0"
first=$(PATH="$SANDBOX/bin:$PATH" TMPDIR="$SANDBOX" TMUX_SLACK_LATER_WORKSPACE="$WORKSPACE" \
  sh -c "$loadbind" 2>/dev/null)
second=$(PATH="$SANDBOX/bin:$PATH" TMPDIR="$SANDBOX" TMUX_SLACK_LATER_WORKSPACE="$WORKSPACE" \
  sh -c "$loadbind" 2>/dev/null)
check "the first load asks fzf for the real list" \
  "$(printf '%s' "$first" | sed 's/(.*--/(--/')" "reload-sync(--load)"
check "a later load only re-reads the header" \
  "$(printf '%s' "$second" | sed 's/(.*--/(--/')" "transform-header(--header)"

# What that reload actually delivers: the rows fzf swaps in, and the header the
# following load event then reads out of the snapshot it left.
loadcmd=$(printf '%s' "$first" | sed 's/^reload-sync(//; s/)$//')
: >"$CALLED"
fresh=$(PATH="$SANDBOX/bin:$PATH" TMPDIR="$SANDBOX" TMUX_SLACK_LATER_WORKSPACE="$WORKSPACE" \
  sh -c "$loadcmd" 2>/dev/null | plain | cut -f2 | tr '\n' '|')
check "the async load calls the real backend" "$(cat "$CALLED")" "list "
check "the async load returns the fetched rows" "$fresh" "from Slack|also fresh|"
check "the header follows the rows it loaded" "$(run --header | head -1)" "Later · 2"
rm -f "$SANDBOX/bin/fzf"

if ((fail)); then
  echo "FAILED"
  exit 1
fi
echo "All Later pane checks passed."
