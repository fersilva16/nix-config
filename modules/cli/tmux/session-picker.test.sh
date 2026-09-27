#!/usr/bin/env bash
# Self-check for the session picker's tree. Extracts the tmux-wt-pick body
# verbatim from session-picker.nix (so it cannot drift) and renders `--list`
# against a throwaway tmux server. Worth testing because nesting is inferred
# from names alone: a sort or parent-lookup slip silently flattens the tree.
# Run by hand: bash session-picker.test.sh
set -eu

SRC="$(dirname "$0")/session-picker.nix"

PROG=$(awk '
  /tmux-wt-pick = pkgs.writeShellApplication/ { w = 1 }
  w && /text = \047\047/ { c = 1; next }
  c && /^    \047\047;$/ { exit }
  c { print }
' "$SRC")

[[ -z "$PROG" ]] && {
  echo "FAIL: could not extract tmux-wt-pick body from $SRC"
  exit 1
}

# Undo Nix's ''${...} escaping so the body is runnable bash.
PROG=${PROG//\'\'\$\{/\$\{}

# Private tmux server: TMUX_TMPDIR moves the socket, unsetting TMUX detaches
# from the caller's server.
TMUX_TMPDIR=$(mktemp -d)
export TMUX_TMPDIR
unset TMUX
trap 'tmux kill-server 2>/dev/null || true; rm -rf "$TMUX_TMPDIR"' EXIT

# "a/gone/orphan": parent session missing → hangs off the nearest one ("a").
# "a-b": must not split a's subtree. "z/lonely": no ancestor → flat, full name.
# "pocket" and "_lazygit-1": popup-only sessions, never listed.
for s in a a/x a/x/l1 a/x/l2 a/y a-b a/gone/orphan z/lonely pocket _lazygit-1; do
  tmux new-session -d -s "$s" -c /tmp
done

# Field 2 is the display; drop colors and the current-session marker.
got=$(bash -euo pipefail -c "$PROG" pick --list | cut -f2 |
  sed -e $'s/\x1b\\[[0-9;]*m//g' -e 's/^● /  /')

want='  a
    ├─ gone/orphan
    ├─ x
    │  ├─ l1
    │  └─ l2
    └─ y
  a-b
  z/lonely'

if [[ "$got" == "$want" ]]; then
  echo "ok"
else
  printf 'FAIL\n--- want\n%s\n--- got\n%s\n' "$want" "$got"
  exit 1
fi
