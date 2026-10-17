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
for s in a a/x a/x/l1 a/x/l2 a/y a-b a/gone/orphan z/lonely; do
  tmux new-session -d -s "$s" -c /tmp
done

# Peers close the list; the back row shows only for a session a hop reached.
tmux set -g @hop-peers "polaris mars"
tmux set-environment -t "$(tmux display-message -p '#S')" TMUX_HOP_FROM vega

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
  z/lonely
  polaris ⇢
  mars ⇢
  vega ⇠'

if [[ "$got" != "$want" ]]; then
  printf 'FAIL\n--- want\n%s\n--- got\n%s\n' "$want" "$got"
  exit 1
fi

# The binding runs the popup through run-shell, which shows a non-zero
# exit as an error: a cancelled fzf (130) exits 0, a failed one keeps its exit.
# The picker runs itself ("$0" --list), so it needs a path here.
mkdir "$TMUX_TMPDIR/bin"
pick="$TMUX_TMPDIR/bin/tmux-wt-pick"
printf '#!/usr/bin/env bash\nset -euo pipefail\n%s\n' "$PROG" >"$pick"
# shellcheck disable=SC2016  # $FZF_EXIT expands in the fake fzf, not here
printf '#!/bin/sh\ncat >/dev/null\nexit "$FZF_EXIT"\n' >"$TMUX_TMPDIR/bin/fzf"
chmod +x "$pick" "$TMUX_TMPDIR/bin/fzf"
for want in 130:0 2:2; do
  got=0
  FZF_EXIT=${want%:*} PATH="$TMUX_TMPDIR/bin:$PATH" "$pick" || got=$?
  if [[ "$got" != "${want#*:}" ]]; then
    printf 'FAIL fzf exit %s: picker exited %s, want %s\n' "${want%:*}" "$got" "${want#*:}"
    exit 1
  fi
done

echo "ok"
