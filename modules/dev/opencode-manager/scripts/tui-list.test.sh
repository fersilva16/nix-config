#!/usr/bin/env bash
# Self-check for the `tui --list` jq program. Extracts it verbatim from
# opencode-manager.sh (so it cannot drift) and feeds it synthetic sessions and
# notifications. Run by hand: bash tui-list.test.sh
set -eu

SRC="$(dirname "$0")/opencode-manager.sh"

PROG=$(awk "/^      '\$/{f=!f; next} f" "$SRC")
[[ -z "$PROG" ]] && {
  echo "FAIL: could not extract jq program from $SRC"
  exit 1
}

DIM=$'\033[2m'
RST=$'\033[0m'
GRN=$'\033[32m'
YEL=$'\033[33m'
RED=$'\033[31m'

# $4 = collapse (1 = browsing, 0 = filtering)
run() {
  jq -rn --argjson sess "$1" --argjson notifs "$2" --arg cur "$3" \
    --argjson collapse "$4" \
    --arg dim "$DIM" --arg rst "$RST" --arg grn "$GRN" --arg yel "$YEL" --arg red "$RED" \
    "$PROG"
}

strip() { sed $'s/\033\\[[0-9;]*m//g'; }

fail() {
  echo "FAIL: $1"
  exit 1
}

SESS='[
  {"session":"omo","target":"omo:10","status":"idle","title":"tenth window"},
  {"session":"omo","target":"omo:2","status":"generating","title":"bump deps"},
  {"session":"omo","target":"omo:5","status":"idle","title":"middle window"},
  {"session":"omo/wt-b","target":"omo/wt-b:1","status":"idle","title":""},
  {"session":"omo/wt-a","target":"omo/wt-a:1","status":"idle","title":"needs permission"},
  {"session":"omo/wt-a","target":"omo/wt-a:7","status":"idle","title":"sibling pane"},
  {"session":"solo/only-wt","target":"solo/only-wt:1","status":"generating","title":"rootless worktree"},
  {"session":"zeta","target":"zeta:1","status":"idle","title":"zeta first"},
  {"session":"zeta","target":"zeta:2","status":"idle","title":"zeta last row overall"}
]'
NOTIFS='[
  {"target":"omo/wt-a:1","session":"omo/wt-a","event":"permission","message":"rm -rf","timestamp":"2026-08-02T10:00:00Z"},
  {"target":"omo/wt-a:1","session":"omo/wt-a","event":"complete","message":"done","timestamp":"2026-08-02T09:00:00Z"},
  {"target":"ghost:9","session":"ghost","event":"error","message":"boom","timestamp":"2026-08-02T08:00:00Z"}
]'

echo "=== collapsed (browsing), cur=omo:2 ==="
out=$(run "$SESS" "$NOTIFS" "omo:2" 1)
printf '%s\n' "$out"
plain=$(printf '%s\n' "$out" | strip)

echo
echo "=== assertions ==="

# 9 live panes + 1 notification whose pane already exited (still dismissable)
n=$(printf '%s\n' "$out" | grep -c '' || true)
[[ "$n" == 10 ]] || fail "expected 10 rows, got $n"

# tree order: roots alphabetical, windows numeric (:10 last), then children
order=$(printf '%s\n' "$out" | cut -f1 | tr '\n' ' ')
want="ghost:9 omo:2 omo:5 omo:10 omo/wt-a:1 omo/wt-a:7 omo/wt-b:1 solo/only-wt:1 zeta:1 zeta:2 "
[[ "$order" == "$want" ]] || fail "order
  got:  $order
  want: $want"

# the window index never appears in the display column
printf '%s\n' "$plain" | cut -f2 | grep -q ':' && fail "display should never show :N"

col() { printf '%s\n' "$plain" | sed -n "${1}p" | cut -f2; }
at() { awk -v s="$2" '{ print index($0, s) }' <<<"$1"; }

# a multi-pane session names itself once; an extra pane just continues the
# stem, never branching with the ─ stroke a worktree uses
[[ "$(col 2)" == *"omo"* ]] || fail "row 2 should name the omo session"
[[ "$(col 3)" == *"│"* ]] || fail "row 3 (extra pane of omo) should continue the stem"
[[ "$(col 3)" != *"omo"* ]] || fail "row 3 should not repeat the session name"
[[ "$(col 3)" != *"─"* ]] || fail "an extra pane must not branch with a ─ stroke"

# ONE stem: a worktree's ├─ starts in the same column as a pane row's │
stem_pane=$(at "$(col 3)" '│')
stem_wt=$(at "$(col 5)" '├')
[[ "$stem_pane" == "$stem_wt" ]] ||
  fail "stem not continuous: pane rail at $stem_pane, worktree branch at $stem_wt"

# depth is rail count, not a marker: a nested pane keeps the root stem AND
# draws its own rail under the worktree name, so it cannot read as a root pane
[[ "$(at "$(col 6)" '│')" == "$stem_pane" ]] || fail "nested pane lost the root stem"
leafcol=$(at "$(col 5)" 'wt-a')
[[ "$(at "$(col 6)" '└')" == "$leafcol" ]] ||
  fail "nested pane rail should sit under the worktree name at $leafcol"
[[ "$(col 3)" != "$(col 6)" ]] || fail "root pane and nested pane must not look alike"

# worktrees branch with ├─, the last one closes with └─
[[ "$(col 5)" == *"├─ wt-a"* ]] || fail "row 5 should be ├─ wt-a"
[[ "$(col 7)" == *"└─ wt-b"* ]] || fail "row 7 should be └─ wt-b (last child)"

# the stem closes with └ when the group's last row is a pane, not a worktree
[[ "$(col 10)" == *"└"* ]] || fail "row 10 should close the root stem with └"
[[ "$(col 10)" != *"─"* ]] || fail "row 10 is a pane continuing, not a branch"
[[ "$(col 4)" == *"│"* ]] || fail "row 4 is mid-group, stem should stay │"

# a worktree whose root session has no pane keeps its full name, no connector
[[ "$(col 8)" == *"solo/only-wt"* ]] || fail "rootless worktree should show its full name"
[[ "$(col 8)" != *"─"* ]] || fail "rootless worktree should get no connector"

# the current-pane marker lands on exactly one row, the current one
marked=$(printf '%s\n' "$out" | grep -cF "${GRN}●${RST} " || true)
[[ "$marked" == 1 ]] || fail "expected 1 current marker, got $marked"
printf '%s\n' "$out" | sed -n 2p | grep -qF "omo:2	${GRN}●${RST}" || fail "marker not on current row"

# highest-severity notification wins per target: permission ⏸ beats complete ●
printf '%s\n' "$plain" | sed -n 5p | grep -q '⏸' || fail "wt-a should show ⏸"
# a notification outranks the busy spinner
printf '%s\n' "$plain" | sed -n 1p | grep -q '‼' || fail "ghost:9 should show ‼"
# an empty title renders as a dash, not a blank gap
printf '%s\n' "$plain" | sed -n 7p | grep -q '—' || fail "empty title should render as —"

# titles align: every title starts in the same column, stem and indent included
cols=$(printf '%s\n' "$plain" | cut -f2 |
  awk -F'  +' '{print length($0) - length($NF)}' | sort -u | grep -c '' || true)
[[ "$cols" == 1 ]] || fail "titles not aligned ($cols distinct columns)"

# every row is "target<TAB>display" with a target fzf can hand to switch-client
printf '%s\n' "$out" | awk -F'\t' 'NF != 2 || $1 == "" { print "bad row: " $0; exit 1 }' ||
  fail "malformed row"

echo "=== expanded (filtering) ==="
exp=$(run "$SESS" "$NOTIFS" "omo:2" 0 | strip)
printf '%s\n' "$exp"

# collapsing must not hide a row from a name search: every row spells out its
# session, so /omo matches all six omo panes rather than just the first
omorows=$(printf '%s\n' "$exp" | cut -f2 | grep -c 'omo' || true)
[[ "$omorows" == 6 ]] || fail "expected 6 rows naming omo when expanded, got $omorows"
printf '%s\n' "$exp" | cut -f2 | grep -q '│' && fail "expanded mode should have no rails"

[[ -z "$(run '[]' '[]' '' 1)" ]] || fail "empty input should render nothing"

echo "ALL OK"
