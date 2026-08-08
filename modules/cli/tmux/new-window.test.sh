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

# Shim every `tmux` call in the body onto the private socket, and stub the
# git-root helper (resolution is its own concern, not this script's).
cat >"$TMP/bin/tmux" <<EOF
#!/bin/sh
exec "$REAL_TMUX" -S "$SOCK" "\$@"
EOF
cat >"$TMP/bin/tmux-git-root-path" <<'EOF'
#!/bin/sh
echo "${1:-.}"
EOF
chmod +x "$TMP/bin/tmux" "$TMP/bin/tmux-git-root-path"
export PATH="$TMP/bin:$PATH"

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
busy=$(tmux display-message -p -t t '#{window_id}')
run "$PROJ" t >/dev/null
check "busy window does not block reuse" 2 "$(count)"
check "reuse selects the idle window, not the busy one" \
  "$(tmux list-windows -t t -F '#{window_id}' | head -1)" \
  "$(tmux display-message -p -t t '#{window_id}')"

# 3. A different root has no idle window, so one is created.
tmux select-window -t "$busy"
run "$OTHER" t >/dev/null
check "different root creates a new window" 3 "$(count)"

# 4. The new window is at the requested root.
check "new window opens at the requested root" "$OTHER" \
  "$(tmux display-message -p -t t '#{pane_current_path}')"

exit "$fail"
