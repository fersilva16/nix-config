#!/usr/bin/env bash
# Self-check for the PR widget's status segment. Builds the real derivation out
# of pr.nix (so it cannot drift from the source the way a transcribed copy
# would) and drives it with fixture caches.
#
# Worth testing because the number carries no label: it claims "this many of
# your open PRs need you", and a filter that lets drafts, green PRs or snoozed
# PRs back in still renders a plausible number while nothing errors. The
# silence at zero has the same property in reverse.
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

GH=$'\uF09B' # nf-fa-github — marks the block; the number itself is bare

fail=0

# Run the widget against a fixture cache and optional snooze list. HOME is
# redirected so the widget never reads the real snooze list — a genuinely
# snoozed fixture URL would otherwise silently drop a row. TMPDIR places the
# cache where ${cache} expects it, and writing it now keeps its mtime inside
# the 2-minute freshness window, so no background refresh is spawned and the
# test never touches the network.
run_with() {
  local cache_json=$1 ignored=${2:-} out sandbox
  sandbox=$(mktemp -d)
  printf '%s' "$cache_json" >"$sandbox/tmux-pr.json"
  mkdir -p "$sandbox/.local/state/tmux-pr"
  printf '%s' "$ignored" >"$sandbox/.local/state/tmux-pr/ignored"
  out=$(HOME="$sandbox" TMPDIR="$sandbox" "$WIDGET/bin/tmux-pr-widget" 2>/dev/null || true)
  rm -rf "$sandbox"
  # Strip tmux style directives; only the icon, number and spacing are tested.
  printf '%s' "$out" | sed 's/#\[[^]]*\]//g'
}

# $1 label, $2 cache, $3 expected (after style stripping), $4 snooze list
expect() {
  local label=$1 got
  got=$(run_with "$2" "${4:-}")
  if [[ "$got" != "$3" ]]; then
    printf 'FAIL: %s\n  expected: %q\n  got:      %q\n' "$label" "$3" "$got"
    fail=1
  else
    printf 'ok: %s\n' "$label"
  fi
}

# $1 number, $2 ci, $3 decision, $4 draft
pr() {
  printf '{"url":"https://example.test/pr/%s","updated":"2026-01-01T00:00:00Z","ci":"%s","decision":"%s","draft":%s}' \
    "$1" "$2" "$3" "$4"
}

green=$(pr 1 SUCCESS APPROVED false)
failing=$(pr 2 FAILURE "" false)
errored=$(pr 3 ERROR REVIEW_REQUIRED false)
changes=$(pr 4 SUCCESS CHANGES_REQUESTED false)
draft=$(pr 5 FAILURE CHANGES_REQUESTED true)
pending=$(pr 6 PENDING "" false)

expect "silent when nothing needs you" \
  "{\"mine\":[$green,$pending],\"reviewed\":[],\"merged\":[]}" \
  ''

expect "failing CI, errored CI and changes requested each count" \
  "{\"mine\":[$green,$failing,$errored,$changes],\"reviewed\":[],\"merged\":[]}" \
  " ${GH} 3 "

expect "a red draft is work in progress, not a signal" \
  "{\"mine\":[$draft,$failing],\"reviewed\":[],\"merged\":[]}" \
  " ${GH} 1 "

# Reviewed and merged PRs are history, never a call to action.
expect "reviewed and merged lists never count" \
  "{\"mine\":[],\"reviewed\":[$failing],\"merged\":[$changes]}" \
  ''

expect "a snoozed PR stops counting until it moves" \
  "{\"mine\":[$failing,$changes],\"reviewed\":[],\"merged\":[]}" \
  " ${GH} 1 " \
  $'https://example.test/pr/2\t2026-01-01T00:00:00Z\n'

expect "a snoozed PR counts again once updatedAt moves" \
  "{\"mine\":[$failing],\"reviewed\":[],\"merged\":[]}" \
  " ${GH} 1 " \
  $'https://example.test/pr/2\t2025-12-31T00:00:00Z\n'

if ((fail)); then
  echo "FAILED"
  exit 1
fi
echo "All PR widget checks passed."
