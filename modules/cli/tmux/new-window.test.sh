#!/usr/bin/env bash
# Self-check for prefix+c window reuse. Extracts the shell body verbatim from
# tmux.nix (so it cannot drift) and drives it against a throwaway tmux server
# on a private socket.
#
# Worth testing because every way this breaks looks like the OLD behaviour: a
# typo in the nested #{&&:} filter matches nothing, the script falls through to
# new-window, and you get a fresh window every time — exactly what you got
# before, so nothing looks wrong. The failure is silent by construction.
# Run by hand: bash new-window.test.sh
set -eu

SRC="$(cd "$(dirname "$0")" && pwd)/tmux.nix"
REAL_TMUX=$(command -v tmux)

PROG=$(awk '
  /tmux-new-window = pkgs.writeShellApplication/ { w = 1 }
  w && /text = \047\047/ { c = 1; next }
  c && /^    \047\047;$/ { exit }
  c { print }
' "$SRC")

[[ -z "$PROG" ]] && {
  echo "FAIL: could not extract tmux-new-window body from $SRC"
  exit 1
}

# Undo Nix's ''${...} escaping so the body is runnable bash.
PROG=${PROG//\'\'\$\{/\$\{}

# run-shell expands #{...} into the command string before /bin/sh parses it, so
# #{session_id} arrives as "01" for session $101 ($1 unset, then "01") and every
# tmux call targets a session that does not exist. Silent for ids $0-$9 (empty
# $N, so the script's own default kicked in), fatal from $10 on.
if grep -n 'run-shell.*#{session_id}' "$SRC"; then
  echo "FAIL: #{session_id} interpolated into a run-shell command (lines above)"
  exit 1
fi
echo "ok   no #{session_id} passed through run-shell"

command -v fish >/dev/null || {
  echo "SKIP: fish not on PATH (the filter matches on pane_current_command)"
  exit 0
}

TMP=$(mktemp -d)
SOCK="$TMP/sock"
PROJ="$TMP/proj"
OTHER="$TMP/other"
mkdir -p "$PROJ" "$OTHER" "$TMP/bin"
# macOS puts mktemp dirs under the /var -> /private/var symlink; tmux reports
# the physical path, so pin the expectations to it.
PROJ=$(cd "$PROJ" && pwd -P)
OTHER=$(cd "$OTHER" && pwd -P)

# Invoked by trap, which shellcheck cannot see.
# shellcheck disable=SC2329
cleanup() {
  "$REAL_TMUX" -S "$SOCK" kill-server 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

# Shim every `tmux` call in the body onto the private socket, and stub git
# (root resolution is its own concern, not this script's).
cat >"$TMP/bin/tmux" <<EOF
#!/bin/sh
exec "$REAL_TMUX" -S "$SOCK" "\$@"
EOF
cat >"$TMP/bin/git" <<'EOF'
#!/bin/sh
echo "$2"
EOF
chmod +x "$TMP/bin/tmux" "$TMP/bin/git"
export PATH="$TMP/bin:$PATH"
# Running this from inside tmux would otherwise leak a pane id from the real
# server, which resolves to nothing on the private socket.
unset TMUX_PANE

# fish explicitly for window 1 (default-command only applies to windows created
# after it is set) and as default-command for the ones the body creates.
tmux -f /dev/null new-session -d -s t -c "$PROJ" fish
tmux set -g default-command fish
# Panes report their real command only once the shell has exec'd.
for _ in $(seq 30); do
  [[ "$(tmux display-message -p -t t '#{pane_current_command}')" == "fish" ]] && break
  sleep 0.1
done

count() { tmux list-windows -t t -F '#{window_id}' | wc -l | tr -d ' '; }
# Read the session's own state. `display-message -t t` resolves through the
# most-recently-used client instead, and on a detached server that reports the
# wrong window about a third of the time.
active() { tmux list-windows -t t -F "$1" -f '#{window_active}'; }
# eval runs in the function's scope, so the body sees $1/$2 as its own args.
run() { (cd "$PROJ" && eval "$PROG"); }

fail=0
check() {
  local label=$1 expect=$2 got=$3
  if [[ "$expect" == "$got" ]]; then
    echo "ok   $label"
  else
    echo "FAIL $label: expected $expect, got $got"
    fail=1
  fi
}

# 1. Sitting on the only (idle) window: prefix+c must not stack a duplicate.
run "$PROJ" t >/dev/null
check "idle window at same root is reused, not duplicated" 1 "$(count)"

# 2. A window running something is not idle — but the idle one is still found
#    from it, rather than a third window being created.
tmux new-window -t t: -c "$PROJ" 'sleep 60'
busy=$(active '#{window_id}')
run "$PROJ" t >/dev/null
check "busy window does not block reuse" 2 "$(count)"
idle_win=$(tmux list-windows -t t -F '#{window_id}' | head -1)
check "reuse selects the idle window, not the busy one" "$idle_win" "$(active '#{window_id}')"

# 3. A different root has no idle window, so one is created.
tmux select-window -t "$busy"
run "$OTHER" t >/dev/null
check "different root creates a new window" 3 "$(count)"

# 4. The new window is at the requested root.
check "new window opens at the requested root" "$OTHER" "$(active '#{pane_current_path}')"

# 5. The keybind passes no args, so both defaults must resolve from TMUX_PANE.
#    The active window is the $OTHER one, so pointing TMUX_PANE at the busy
#    $PROJ window and landing on the idle $PROJ window proves the root came
#    from the invoking pane and not from whatever happened to be active.
TMUX_PANE=$(tmux list-panes -t "$busy" -F '#{pane_id}' | head -1)
export TMUX_PANE
(cd / && eval "$PROG") >/dev/null || echo "FAIL no-arg defaults: exited $?"
check "no-arg run resolves root and session from TMUX_PANE" 3 "$(count)"
check "no-arg run reuses the invoking pane's idle window" "$idle_win" "$(active '#{window_id}')"
unset TMUX_PANE

exit "$fail"
