#!/usr/bin/env bash
# Self-check for per-pane agent session restore. Drives the real resurrect
# save/restore scripts, with the agent options lifted verbatim from
# resurrect.nix, on a throwaway tmux server: two fake `omo` panes in one dir
# with different @oc-sid, save, kill the server, restore, and check each pane
# resumed its own session.
#
# Worth testing because a broken map degrades to `--continue`, the OLD
# behaviour: every pane still comes back running omo, just all in the same
# session, so nothing looks wrong until you read the conversation.
# Run by hand: bash resurrect.test.sh
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/resurrect.nix"
AGENTS="bash $HERE/resurrect-agents.sh"
RESURRECT=${RESURRECT:-$(nix build --no-link --print-out-paths "$HERE/../../..#tmuxPlugins.resurrect")/share/tmux-plugins/resurrect}

TMP=$(mktemp -d)
PROJ="$TMP/proj"
mkdir -p "$PROJ" "$TMP/bin" "$TMP/res"
T() { tmux -L "resurrect-test-$$" "$@"; }
trap 'T kill-server 2>/dev/null || true; rm -rf "$TMP"' EXIT

# Fake agent: records how the restore launched it, then signals the test.
cat >"$TMP/bin/omo" <<EOF
#!/bin/sh
where=\$(tmux display-message -p -t "\$TMUX_PANE" '#{window_index}.#{pane_index}')
echo "\$where \$*" >>"$TMP/launched"
tmux wait-for -S "omo-\$where"
sleep 3600 # not exec: resurrect must see this process as .../omo
EOF
chmod +x "$TMP/bin/omo"
# Every command that spawns a pane passes its own PATH; the real omo must
# never be the one that runs.
export PATH="$TMP/bin:$PATH"

OPTS=$(grep -E "set -g @resurrect-(processes|hook-)" "$SRC" | sed "s|\${agents}|$AGENTS|g")
[ "$(printf '%s\n' "$OPTS" | wc -l)" -eq 3 ] || {
  echo "FAIL: expected 3 agent options in $SRC, got:"
  printf '%s\n' "$OPTS"
  exit 1
}
cat >"$TMP/tmux.conf" <<EOF
set -g default-shell /bin/sh
# Not a login shell: macOS /etc/profile would reset PATH and lose the fake omo.
set -g default-command /bin/sh
set -g @resurrect-dir '$TMP/res'
$OPTS
run-shell $RESURRECT/resurrect.tmux
EOF

start() { T -f "$TMP/tmux.conf" new-session -d -s "$1" -c "$PROJ"; }
wait_for() { timeout 10 tmux -L "resurrect-test-$$" wait-for "$1" || {
  echo "FAIL: pane $1 never started"
  exit 1
}; }
check() {
  if grep -qxF "$2" "$3"; then echo "ok   $1"; else
    echo "FAIL: $1: expected line '$2' in $3:"
    cat "$3"
    exit 1
  fi
}

start work
T split-window -t work:0 -c "$PROJ"
T split-window -t work:0 -c "$PROJ"
T split-window -t work:0 -c "$PROJ"
for p in 0 1 2; do T send-keys -t "work:0.$p" "omo" C-m; done
for p in 0 1 2; do wait_for "omo-0.$p"; done
# Pane 3 is not an agent but mentions one, and carries a stale @oc-sid.
T send-keys -t work:0.3 "sh -c 'exec sleep 3600' omo.nix" C-m
T set-option -p -t work:0.0 @oc-sid sid-A
T set-option -p -t work:0.1 @oc-sid sid-B
T set-option -p -t work:0.3 @oc-sid sid-stale
# Pane 2 never announced a session: must fall back to --continue.

T run-shell "$RESURRECT/scripts/save.sh quiet"
MAP="$(cd "$TMP/res" && pwd -P)/$(readlink "$TMP/res/last").sids"
check "map records pane 0" "$(printf 'work:0.0\tomo\tsid-A')" "$MAP"
check "map records pane 1" "$(printf 'work:0.1\tomo\tsid-B')" "$MAP"
[ "$(wc -l <"$MAP")" -eq 2 ] || {
  echo "FAIL: map has entries for non-agent or sid-less panes:"
  cat "$MAP"
  exit 1
}
echo "ok   map skips sid-less and non-agent panes"

# Same layout, new session in pane 0: resurrect discards the identical save,
# the map of the kept one must still follow. Saves are named by the second, so
# backdate the first one rather than wait for the clock to tick.
old=tmux_resurrect_20000101T000000.txt
mv "$TMP/res/$(readlink "$TMP/res/last")" "$TMP/res/$old"
mv "$MAP" "$TMP/res/$old.sids"
ln -fs "$old" "$TMP/res/last"
T set-option -p -t work:0.0 @oc-sid sid-C
T run-shell "$RESURRECT/scripts/save.sh quiet"
[ "$(readlink "$TMP/res/last")" = "$old" ] || {
  echo "FAIL: identical save was not deduped, the scenario did not happen"
  exit 1
}
MAP="$TMP/res/$old.sids"
check "map follows a deduped save" "$(printf 'work:0.0\tomo\tsid-C')" "$MAP"

T kill-server
: >"$TMP/launched"
start scratch
T run-shell "$RESURRECT/scripts/restore.sh"
for p in 0 1 2; do wait_for "omo-0.$p"; done
check "pane 0 resumes its own session" "0.0 --session sid-C" "$TMP/launched"
check "pane 1 resumes its own session" "0.1 --session sid-B" "$TMP/launched"
check "sid-less pane falls back" "0.2 --continue" "$TMP/launched"
[ -z "$(T show-options -pqv -t work:0.0 @resurrect-agent-sid)" ] || {
  echo "FAIL: resume left @resurrect-agent-sid behind"
  exit 1
}
echo "ok   resume clears its pane stamp"
