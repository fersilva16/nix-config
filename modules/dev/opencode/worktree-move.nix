_: {
  home =
    { lib, userCfg, ... }:
    lib.mkIf userCfg.worktree.enable {
      programs.fish = {
        functions.wtoc = ''
          # Move this repo's opencode session into a worktree, bringing any
          # uncommitted work along.  Fixes the "investigated on main, now I
          # want a PR" case: opencode pins a session to the absolute directory
          # it was created in and never re-resolves it, so resuming inside a
          # worktree still points at the old checkout.
          #
          # Composes `wt` for the worktree + tmux side rather than
          # reimplementing it, then relocates the session through opencode's
          # own move API.
          argparse c/changes -- $argv
          or return 1

          set -l cur_root (git rev-parse --show-toplevel 2>/dev/null)
          or begin
            echo "wtoc: not a git repo"
            return 1
          end

          set -l main_root (git worktree list --porcelain | head -1 | string replace "worktree " "")
          set -l repo_name (basename $main_root)
          set -l wt_dir (dirname $main_root)"/$repo_name.worktrees"

          set -l name $argv[1]
          set -l branch $argv[2]

          # No name: pick an existing worktree, the way `wt` with no args does.
          if test -z "$name"
            if not test -d "$wt_dir"; or test (count (command ls "$wt_dir" 2>/dev/null)) -eq 0
              echo "wtoc: no worktrees yet — use: wtoc [-c] <name> [branch]"
              return 1
            end
            set name (command ls "$wt_dir" | fzf --select-1 --prompt="move session to> " --height=40%)
            or return 1
          end

          set -l wt_path "$wt_dir/$name"

          if test "$wt_path" = "$cur_root"
            echo "wtoc: already in worktree '$name'"
            return 1
          end

          # Candidates are top-level sessions only.  Subagent sessions are
          # children and are usually the most recently touched rows for a
          # directory, so an unfiltered "latest session" picks the wrong one.
          set -l db "$HOME/.local/share/opencode/opencode.db"
          set -l rows (sqlite3 -separator \t "$db" \
            "SELECT id, title FROM session
             WHERE directory = '$cur_root' AND parent_id IS NULL
             ORDER BY time_updated DESC LIMIT 20" 2>/dev/null)

          if test -z "$rows"
            echo "wtoc: no opencode session found for $cur_root"
            return 1
          end

          set -l ids (printf '%s\n' $rows | string split -f1 \t)

          # Prefer the session this tmux session is actually running (@oc-sid,
          # bound by the notifier plugin).  It is unset for panes opencode
          # never emitted a session.created for, and one repo can host several
          # instances — so ask instead of guessing when it does not pin down.
          set -l sid
          if set -q TMUX
            # This pane's own claim wins: exact both when run from inside
            # opencode (its shell inherits TMUX_PANE) and when run in the pane
            # opencode was quit in, since nothing clears @oc-sid on exit.
            if set -q TMUX_PANE
              set -l own (command tmux show-options -pv -t "$TMUX_PANE" @oc-sid 2>/dev/null)
              contains -- "$own" $ids; and set sid $own
            end
            if test -z "$sid"
              for pane_sid in (command tmux list-panes -s -F '#{@oc-sid}' 2>/dev/null)
                if contains -- "$pane_sid" $ids
                  set sid $pane_sid
                  break
                end
              end
            end
          end

          if test -z "$sid"
            set -l pick (printf '%s\n' $rows |
              fzf --select-1 --delimiter=\t --with-nth=2.. --prompt="move session> " --height=40%)
            or return 1
            set sid (string split -f1 \t -- "$pick")
          end

          set -l title (sqlite3 "$db" "SELECT title FROM session WHERE id = '$sid'" 2>/dev/null)
          set -l dirty (git -C "$cur_root" status --porcelain | wc -l | string trim)

          # Note the session we came from before wt switches away, so we can
          # warn about a TUI left behind on the old path.
          set -l src_session
          if set -q TMUX
            set src_session (command tmux display-message -p '#{session_name}')
          end

          # Worktree + tmux session, including switching to it.
          #
          # WT_SYNC because wt builds in the background by default: it creates
          # the directory up front so the new tmux session can start inside it,
          # then checks out detached.  Moving a session into that tree before
          # the checkout lands points it at an empty directory — and with -c,
          # patches one.  WT_SYNC waits for the checkout only, so .setup still
          # runs in the background and this never blocks on `pnpm i`.
          echo "wtoc: preparing worktree '$name'…"
          WT_SYNC=1 wt $name $branch

          # Gate on .git — a *file* in a linked worktree — rather than on wt's
          # status or on the directory.  The directory now always exists, and
          # wt ends on tmux, so it reports failure when no client is attached
          # even though the worktree is fine.
          if not test -e "$wt_path/.git"
            echo "wtoc: worktree '$name' was not created — see $wt_dir/.$name.log"
            return 1
          end

          # ponytail: the move API needs a live server and a running TUI only
          # serves /health on its own port, so spin a throwaway one (~1s) and
          # kill it.  If the shared server is ever enabled
          # (opencode.server.autoAttach), point $base at :4096 and drop this.
          set -l port (random 40000 60000)
          set -l log (mktemp)
          opencode serve --port $port >$log 2>&1 &
          set -l srv $last_pid

          set -l base "http://127.0.0.1:$port"
          set -l ready 0
          for i in (seq 100)
            if curl -s -m 1 -o /dev/null "$base/doc" 2>/dev/null
              set ready 1
              break
            end
            sleep 0.1
          end

          if test $ready -eq 0
            echo "wtoc: opencode server did not start"
            cat $log
            kill $srv 2>/dev/null
            rm -f $log
            return 1
          end

          # moveChanges relocates uncommitted work and resets the source tree,
          # so it stays opt-in (-c) — otherwise an unrelated half-finished edit
          # in the source would be swept along.  It is applied to the
          # destination before the move is published, so a failed apply leaves
          # the session where it was.
          set -l move_changes false
          set -q _flag_changes; and set move_changes true

          set -l out (mktemp)
          set -l code (curl -s -m 120 -o $out -w '%{http_code}' \
            -X POST "$base/experimental/control-plane/move-session" \
            -H 'content-type: application/json' \
            -d (printf '{"sessionID":"%s","destination":{"directory":"%s"},"moveChanges":%s}' \
                  "$sid" "$wt_path" "$move_changes"))

          kill $srv 2>/dev/null
          rm -f $log

          # The destination patch is applied before the move is published, so
          # a failure here leaves the session and both trees untouched.
          if test "$code" != 204
            echo "wtoc: move failed — session stayed in $cur_root"
            echo "  "(jq -r '.data.message // .' <$out 2>/dev/null; or cat $out)
            rm -f $out
            return 1
          end
          rm -f $out

          echo "Moved \"$title\" → $name"
          if test "$dirty" -gt 0
            if set -q _flag_changes
              echo "  brought $dirty uncommitted file(s) along"
            else
              echo "  left $dirty uncommitted file(s) behind — -c carries them over"
            end
          end

          # A TUI that was running the session keeps its old directory in
          # memory — it does not fail, it just silently edits the wrong tree.
          if test -n "$src_session"
            and command tmux list-panes -s -t "=$src_session" -F '#{pane_current_command}' 2>/dev/null |
              string match -qr opencode
            echo "  heads-up: opencode is still open in $src_session on the old path — close it"
          end

          if set -q TMUX
            set -l parent (command tmux display-message -p '#{session_name}' | string split -m 1 '/')[1]
            set -l target "=$parent/$name"
            # wt returns early when the worktree session already exists, and
            # that session is usually already running opencode — send-keys
            # would type into its TUI, so take a fresh window instead.
            if command tmux list-panes -t "$target" -F '#{pane_current_command}' 2>/dev/null |
                string match -qr opencode
              command tmux new-window -t "$target" -c "$wt_path" "opencode --session $sid"
            else
              # "=name" is a session target; send-keys resolves a pane, so it
              # needs the trailing ":" to mean "that session's active pane".
              command tmux send-keys -t "$target:" "opencode --session $sid" Enter
            end
          else
            echo "  resume with: cd $wt_path; and opencode --session $sid"
          end
        '';

        # Same arguments as wt: existing worktree names, then branches.
        shellInit = ''
          complete -f -c wtoc -s c -l changes -d "Carry uncommitted changes over to the worktree"
          complete -f -c wtoc -n "test (count (commandline -opc)) -eq 1" -a '(
            set -l mr (git worktree list --porcelain 2>/dev/null | head -1 | string replace "worktree " "")
            set -l rn (basename $mr 2>/dev/null)
            set -l wd (dirname $mr 2>/dev/null)/$rn.worktrees
            test -d $wd 2>/dev/null; and command ls $wd 2>/dev/null
          )'
          complete -f -c wtoc -n "test (count (commandline -opc)) -eq 2" -a '(git branch -a --format="%(refname:short)" 2>/dev/null | string replace -r "^origin/" "" | sort -u | grep -v "^HEAD")'
        '';
      };
    };
}
