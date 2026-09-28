#!/usr/bin/env bash
# Resume every agent pane (omo, opencode) into ITS OWN session after a
# tmux-resurrect restore. `--continue` resumes the cwd's newest session, so
# several agent panes in one project all came back as the same one.
#
# The harnesses publish their session id as the pane option @oc-sid. Three
# resurrect hooks carry it across a restart:
#
#   save <last>     post-save-all: write "<save file>.sids", one line per agent
#                   pane: session:window.pane<TAB>harness<TAB>sid
#   restore <last>  pre-restore-pane-processes: panes exist now, processes are
#                   not started yet; stamp each pane with @resurrect-agent-sid
#   resume <cmd>    the restore command for agent panes: exec
#                   `<cmd> --session <sid>`, or `--continue` when unstamped
#
# The map is keyed to the save file `last` points at, not to "now": resurrect
# drops a save identical to the previous one and leaves `last` on the old file,
# so rewriting that file's map keeps it current even when the layout (and so
# the save) did not change but a pane switched sessions. Restore reads the map
# of the exact file it restores from, and hands it to the pane as a pane option
# before the command runs, so a continuum auto-save landing mid-restore cannot
# swap the map underneath it.
#
# <last> is resurrect's `last` symlink, passed by the hook as
# "$(last_resurrect_file)" (hooks are eval'd inside resurrect's scripts), so
# this never guesses @resurrect-dir.
#
# No runtimeInputs on purpose: `resume` execs the agent, and a PATH prefix
# would leak into the agent's environment.
set -euo pipefail

# The file `last` points at. resurrect links it with a bare basename.
save_file() {
  local target
  target=$(readlink "$1") || return 1
  case $target in
  /*) printf '%s\n' "$target" ;;
  *) printf '%s/%s\n' "$(dirname "$1")" "$target" ;;
  esac
}

save() {
  local file map
  file=$(save_file "$1") || return 0 # nothing saved yet
  map="$file.sids"
  # Harness comes from the command resurrect just saved, with the same
  # `/<name>( |$)` rule as @resurrect-processes, so a pane only gets an entry when
  # its restore rule will actually run `resume`. Field 11 is ":<full command>".
  tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}	#{@oc-sid}' |
    awk -F '\t' '
      NR == FNR { if ($2 != "") sid[$1] = $2; next }
      $1 == "pane" {
        key = $2 ":" $3 "." $6
        cmd = substr($11, 2)
        h = ""
        if (cmd ~ /\/omo / || cmd ~ /\/omo$/) h = "omo"
        else if (cmd ~ /\/opencode / || cmd ~ /\/opencode$/) h = "opencode"
        if (h != "" && key in sid) print key "\t" h "\t" sid[key]
      }' - "$file" >"$map.tmp"
  mv "$map.tmp" "$map"
  # resurrect prunes old saves; drop the maps it orphaned.
  local m
  for m in "$(dirname "$file")"/*.sids; do
    [ -e "${m%.sids}" ] || rm -f "$m"
  done
}

restore() {
  local file pane harness sid
  file=$(save_file "$1") || return 0
  [ -f "$file.sids" ] || return 0
  while IFS=$'\t' read -r pane harness sid; do
    # A pane past the restored layout's pane limit is not recreated; resurrect
    # skips its process too, so there is nothing to stamp.
    tmux set-option -p -t "=$pane" @resurrect-agent-sid "$harness $sid" 2>/dev/null || true
  done <"$file.sids"
}

resume() {
  local harness=$1 saved
  saved=$(tmux show-options -pqv -t "$TMUX_PANE" @resurrect-agent-sid)
  tmux set-option -pu -t "$TMUX_PANE" @resurrect-agent-sid
  if [ "${saved%% *}" = "$harness" ]; then
    exec "$harness" --session "${saved#* }"
  fi
  exec "$harness" --continue
}

case ${1:-} in
save | restore | resume) "$@" ;;
*)
  echo "usage: ${0##*/} save <last> | restore <last> | resume <omo|opencode>" >&2
  exit 2
  ;;
esac
