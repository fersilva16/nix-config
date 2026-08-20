#!/usr/bin/env bash
# Fixture test for the set logic in todoist-mirror.nix.
#
# The mirror's add path is self-evident the first time you run it: everything
# shows up. The close path is not — it only fires once something has already
# been mirrored, so the first real run exercises none of it, and it is the only
# half that can destroy something. This pins it against fixtures instead.
#
# Pure jq/comm, no network, no Todoist, no Linear. Run by hand after touching
# the jq filters:
#
#   bash modules/dev/linear/todoist-mirror-test.sh
#
# Keep the filters here identical to the ones in todoist-mirror.nix.
set -euo pipefail

unwrap='(if type == "array" then . else (.results // []) end)'

pass=0
fail=0

check() {
  if [ "$2" = "$3" ]; then
    printf '  ok   %s\n' "$1"
    pass=$((pass + 1))
  else
    printf '  FAIL %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"
    fail=$((fail + 1))
  fi
}

# ENG-1 is still open, ENG-2 is new, ENG-3 has left the open list -> must close.
linear='[
  {"identifier":"ENG-1","title":"stays","priority":2},
  {"identifier":"ENG-2","title":"is new","priority":0}
]'

# t9 is a hand-written personal task and must be untouchable.
# t7 looks mirrored but lives in another project, so it is out of scope.
todoist='{"results":[
  {"id":"t1","content":"ENG-1 stays","projectId":"P"},
  {"id":"t3","content":"ENG-3 gone","projectId":"P"},
  {"id":"t9","content":"buy oat milk","projectId":"P"},
  {"id":"t7","content":"ENG-9 other project","projectId":"OTHER"}
]}'
pid=P

open=$(jq -r '.[].identifier' <<<"$linear" | sort -u)
mirrored=$(jq -r --arg p "$pid" \
  "$unwrap"' | map(select(.projectId == $p)) | .[].content' <<<"$todoist" |
  grep -oE '^[A-Z]+-[0-9]+' | sort -u || true)

flatten() { tr '\n' ' ' | sed 's/^ *//; s/ *$//'; }

adds=$(comm -23 <(printf '%s\n' "$open") <(printf '%s\n' "$mirrored") | flatten)
closes=$(comm -13 <(printf '%s\n' "$open") <(printf '%s\n' "$mirrored") | flatten)

check "adds only the new issue" "$adds" "ENG-2"
check "closes the issue no longer open" "$closes" "ENG-3"

# The close path has to resolve a real task id, scoped to the project.
tid=$(jq -r --arg i "ENG-3" --arg p "$pid" \
  "$unwrap"' | map(select(.projectId == $p and (.content | startswith($i + " ")))) | .[0].id // empty' \
  <<<"$todoist")
check "close resolves the right task id" "$tid" "t3"

# The two safety rails: a personal task is never mirrored, and neither is a
# mirrored-looking task sitting in some other project.
check "personal task not seen as mirrored" \
  "$(printf '%s' "$mirrored" | grep -c 'buy' || true)" "0"
check "other project excluded" \
  "$(printf '%s' "$mirrored" | grep -c 'ENG-9' || true)" "0"

# First run: nothing mirrored yet, so everything adds and NOTHING closes.
m0=$(jq -r --arg p "$pid" "$unwrap"' | map(select(.projectId == $p)) | .[].content' \
  <<<'{"results":[]}' | grep -oE '^[A-Z]+-[0-9]+' | sort -u || true)
check "first run closes nothing" \
  "$(comm -13 <(printf '%s\n' "$open") <(printf '%s\n' "$m0") | flatten)" ""
check "first run adds everything" \
  "$(comm -23 <(printf '%s\n' "$open") <(printf '%s\n' "$m0") | flatten)" "ENG-1 ENG-2"

# Linear reachable but empty (everything genuinely done): close the mirrored
# tasks, and only those.
o2=$(jq -r '.[].identifier' <<<'[]' | sort -u)
check "empty Linear closes mirrored only" \
  "$(comm -13 <(printf '%s\n' "$o2") <(printf '%s\n' "$mirrored") | flatten)" "ENG-1 ENG-3"

# Linear 1..4 is Urgent..Low and maps onto Todoist p1..p4; 0 means "no
# priority" there and must be omitted rather than flattened into p4.
while read -r lin_priority want; do
  [ -n "$lin_priority" ] || continue
  got=$(jq -r '(.priority // 0) | if . >= 1 and . <= 4 then "p\(.)" else "" end' \
    <<<"{\"priority\":$lin_priority}")
  check "priority $lin_priority maps correctly" "$got" "$want"
done <<'EOF'
1 p1
2 p2
3 p3
4 p4
0
EOF

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
