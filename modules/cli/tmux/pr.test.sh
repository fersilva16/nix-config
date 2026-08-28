#!/usr/bin/env bash
# Self-check for the PR widget's status segment. Builds the real derivation out
# of pr.nix (so it cannot drift from the source the way a transcribed copy
# would) and drives it with fixture caches.
#
# Worth testing because the numbers carry no labels: only their position says
# which is the review queue, which is opened-today and which is reviewed-today.
# A change that lets one of them hide at zero shifts the other two a slot left
# and silently changes what the row means — it still renders, still looks
# plausible, and nothing errors. The whole-segment silence at zero has the same
# property in reverse: it is indistinguishable from a quiet day.
#
# Run by hand: bash pr.test.sh
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
SRC="$HERE/pr.nix"

[[ -f "$SRC" ]] || {
  echo "FAIL: $SRC not found"
  exit 1
}

# Built rather than extracted: the widget body is full of Nix interpolations
# (${cache}, ${jqIgnore}, the refresh store path), and a test that rewrites
# those by hand is testing its own sed, not the widget. Cheap after the first
# run — nix serves it from the store. The nixpkgs rev comes from flake.lock so
# the test builds against the same nixpkgs as a rebuild would, and getFlake on
# the pinned rev sidesteps `path:` fetching the repo (which trips over
# .git/fsmonitor--daemon.ipc, an unsupported file type).
REV=$(jq -r '.nodes[.nodes.root.inputs.nixpkgs].locked.rev' "$REPO/flake.lock")
WIDGET=$(nix build --impure --no-link --print-out-paths --expr "
  let
    pkgs = (builtins.getFlake \"github:NixOS/nixpkgs/$REV\").legacyPackages.aarch64-darwin;
    mod = import $SRC { inherit pkgs; };
  in
  builtins.elemAt mod.home.home.packages 1
" 2>/dev/null)

[[ -n "$WIDGET" && -x "$WIDGET/bin/tmux-pr-widget" ]] || {
  echo "FAIL: could not build tmux-pr-widget from $SRC"
  exit 1
}

GH=$'\uF09B' # nf-fa-github — marks the block; the numbers themselves are bare

fail=0

# Run the widget against a fixture cache. HOME is redirected so the widget reads
# an empty snooze list instead of the real one — otherwise a genuinely snoozed
# fixture URL would silently drop a row and read as a rendering bug. TMPDIR
# places the cache where ${cache} expects it, and writing it now keeps its mtime
# inside the 2-minute freshness window, so no background refresh is spawned and
# the test never touches the network.
run_with() {
  local cache_json=$1 out sandbox
  sandbox=$(mktemp -d)
  printf '%s' "$cache_json" >"$sandbox/tmux-pr.json"
  out=$(HOME="$sandbox" TMPDIR="$sandbox" "$WIDGET/bin/tmux-pr-widget" 2>/dev/null || true)
  rm -rf "$sandbox"
  # Strip tmux style directives; only the icon, numbers and spacing are tested.
  printf '%s' "$out" | sed 's/#\[[^]]*\]//g'
}

# $1 label, $2 cache, $3 expected (after style stripping)
expect() {
  local label=$1 got
  got=$(run_with "$2")
  if [[ "$got" != "$3" ]]; then
    printf 'FAIL: %s\n  expected: %q\n  got:      %q\n' "$label" "$3" "$got"
    fail=1
  else
    printf 'ok: %s\n' "$label"
  fi
}

# One un-snoozed, non-context PR is one unit of queue.
pr='{"url":"https://example.test/pr/1","updated":"2026-01-01T00:00:00Z","context":false}'
pr2='{"url":"https://example.test/pr/2","updated":"2026-01-01T00:00:00Z","context":false}'

expect "silent only when the queue and both tallies are zero" \
  '{"review":[],"mine":[],"today":{"opened":0,"reviewed":0}}' \
  ''

# The order is queue, opened, reviewed, and it is the only thing distinguishing
# them now that the numbers are unlabelled. The slashes bind them into one
# value so the row does not read as three separate widgets.
expect "queue, then opened, then reviewed, slash-joined" \
  "{\"review\":[$pr],\"mine\":[],\"today\":{\"opened\":3,\"reviewed\":7}}" \
  " ${GH} 1/3/7 "

# Each of the next three pins one slot at zero. Together they are the real
# regression net: any of them collapsing to a two-number row means a reader can
# no longer tell which number they are looking at.
expect "a zero queue still holds its slot" \
  '{"review":[],"mine":[],"today":{"opened":2,"reviewed":5}}' \
  " ${GH} 0/2/5 "

expect "a zero opened still holds its slot" \
  "{\"review\":[$pr,$pr2],\"mine\":[],\"today\":{\"opened\":0,\"reviewed\":5}}" \
  " ${GH} 2/0/5 "

expect "a zero reviewed still holds its slot" \
  "{\"review\":[$pr],\"mine\":[],\"today\":{\"opened\":4,\"reviewed\":0}}" \
  " ${GH} 1/4/0 "

# A cache written by the previous build survives one rebuild without .today.
# It must degrade to zeroed tallies, not to an empty status bar.
expect "cache with no today key zeroes the tallies" \
  "{\"review\":[$pr],\"mine\":[]}" \
  " ${GH} 1/0/0 "

# A context parent is a tree-readability row, never assigned to you.
expect "context parents stay out of the queue count" \
  '{"review":[{"url":"https://example.test/pr/9","updated":"2026-01-01T00:00:00Z","context":true}],"mine":[],"today":{"opened":0,"reviewed":0}}' \
  ''

if ((fail)); then
  echo "FAILED"
  exit 1
fi
echo "All PR widget checks passed."
