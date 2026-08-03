#!/usr/bin/env bash
# Self-check for the disk widget thresholds. Extracts the shell body verbatim
# from statusbar.nix (so it cannot drift) and drives every band with a stubbed
# df. Worth testing because the widget's healthy state is *no output* — a typo'd
# threshold looks exactly like "disk is fine" until the disk is full.
# Run by hand: bash statusbar.test.sh
set -eu

SRC="$(dirname "$0")/statusbar.nix"

PROG=$(awk '
  /tmux-disk-widget = pkgs.writeShellApplication/ { w = 1 }
  w && /text = \047\047/ { c = 1; next }
  c && /^    \047\047;$/ { exit }
  c { print }
' "$SRC")

[[ -z "$PROG" ]] && {
  echo "FAIL: could not extract tmux-disk-widget body from $SRC"
  exit 1
}

# Undo Nix's ''${...} escaping so the body is runnable bash.
PROG=${PROG//\'\'\$\{/\$\{}

YELLOW="#d0a215"
ORANGE="#da702c"
RED="#d14d41"

fail=0

# Run the widget with df stubbed to report $1 GiB available. Subshell so the
# widget's `exit 0` (its silent path) does not kill the test run.
run_at() {
  local gib=$1
  (
    # Shadows the real df for the widget body below. Invoked indirectly via
    # eval, which shellcheck cannot see.
    # shellcheck disable=SC2329
    df() {
      printf 'Filesystem 1K-blocks Used Available Use%% Mounted\n'
      printf '/dev/disk3s1s1 971350180 603638376 %d 63%% /\n' "$(( gib * 1048576 ))"
    }
    eval "$PROG"
  )
}

check() {
  local gib=$1 expect=$2 label=$3 out
  out=$(run_at "$gib")
  if [[ "$expect" == "SILENT" ]]; then
    if [[ -n "$out" ]]; then
      echo "FAIL ${label} (${gib}G): expected silence, got: ${out}"
      fail=1
    else
      echo "ok   ${label} (${gib}G): silent"
    fi
  elif [[ "$out" != *"$expect"* ]]; then
    echo "FAIL ${label} (${gib}G): expected ${expect}, got: ${out:-<silence>}"
    fail=1
  else
    echo "ok   ${label} (${gib}G)"
  fi
}

check 350 SILENT     "healthy"
check 100 SILENT     "boundary: 100G still silent"
check 99  "$YELLOW"  "yellow band"
check 50  "$YELLOW"  "boundary: 50G yellow"
check 49  "$ORANGE"  "orange band"
check 25  "$ORANGE"  "boundary: 25G orange (nix min-free)"
check 24  "$RED"     "red band"
check 20  "$RED"     "the 22G state that started this"

# A malformed df must stay silent rather than render garbage in the status bar.
out=$(
  # shellcheck disable=SC2329
  df() { printf 'Filesystem 1K-blocks Used Available Use%% Mounted\n'; }
  eval "$PROG"
)
if [[ -n "$out" ]]; then
  echo "FAIL malformed df: expected silence, got: ${out}"
  fail=1
else
  echo "ok   malformed df: silent"
fi

exit "$fail"
