{
  mkUserModule,
  pkgs,
  ...
}:
let
  # Rows for the worktree pickers: "name  *  2 days ago", most recent first.
  #
  # Sorted by commit epoch, not by the rendered string ("2 weeks ago" doesn't
  # collate), then by name to break ties. Both keys are explicit because the
  # rows are produced in parallel and so arrive in nondeterministic order —
  # the old code leaned on a stable sort preserving the glob's alphabetical
  # order, which parallelism destroys. Getting this wrong doesn't corrupt
  # anything, it just reshuffles rows under the cursor when the async pass
  # swaps in.
  #
  # `*` is the *same* status check wtrm gates --force on, so the marker can
  # never disagree with what removal will actually do. It's also the only slow
  # part: a working-tree scan, ~150ms per worktree, ~2.5s across a 17-worktree
  # monorepo.
  #
  # Two things fix that, and the order matters — measured on that monorepo:
  #
  #   serial, no fsmonitor          2571ms   (what this used to be)
  #   parallel alone, -P 16         1474ms   1.7x
  #   core.fsmonitor alone           757ms   3.4x
  #   both                           126ms   20x
  #
  # Parallelism alone really does plateau at ~1.7x, which is what an earlier
  # note here concluded before giving up on it. But the thing it was
  # contending on was the working-tree scan, and core.fsmonitor (set in
  # modules/dev/git.nix) deletes that scan rather than sharing it out. With
  # the scan gone there's nothing left to serialise on, so the two compound
  # instead of overlapping. Don't reintroduce one without the other and
  # re-measure — either alone looks disappointing.
  #
  # --fast stays anyway: identical layout minus the scan, so the picker opens
  # on it immediately and swaps in the marks afterwards. It's cheap insurance
  # for repos where fsmonitor isn't running yet (the daemon's first call still
  # pays a full scan while it warms up).
  wt-rows = pkgs.writeShellApplication {
    name = "wt-rows";
    runtimeInputs = [
      pkgs.git
      pkgs.bash
    ];
    text = ''
      # usage: wt-rows [--fast] <worktrees-dir>
      fast=""
      if [ "''${1:-}" = "--fast" ]; then
        fast=1
        shift
      fi

      wd="''${1:-}"
      [ -d "$wd" ] || exit 0

      # One row. Runs in an xargs child, so everything it needs is exported.
      row() {
        path="$1"
        name="''${path##*/}"

        # --no-optional-locks: this is a read-only probe, so don't take the
        # index lock or write the refreshed index back.
        mark=" "
        if [ -z "$fast" ] &&
          [ -n "$(git --no-optional-locks -C "$path" status --porcelain 2>/dev/null || true)" ]; then
          mark="*"
        fi

        # Epoch and relative date out of one log call; the epoch is only a sort
        # key, stripped below. A worktree git can't read sorts oldest.
        meta="$(git -C "$path" log -1 --format='%ct %cr' 2>/dev/null || true)"
        stamp="''${meta%% *}"
        [ -n "$stamp" ] || stamp=0

        # Single write, ~55 bytes. Under PIPE_BUF (512 on darwin) a pipe write
        # is atomic, so parallel children can't interleave halves of a row.
        printf '%s\t%-24s %s  %s\n' "$stamp" "$name" "$mark" "''${meta#* }"
      }
      export -f row
      export fast

      for dir in "$wd"/*/; do
        path="''${dir%/}"
        # An empty dir leaves the glob unmatched, expanding to the pattern
        if [ "''${path##*/}" = "*" ]; then continue; fi
        printf '%s\n' "$path"
      done \
        | xargs -P "$(sysctl -n hw.ncpu 2>/dev/null || echo 8)" -I{} bash -c 'row "$@"' _ {} \
        | sort -t"$(printf '\t')" -k1,1rn -k2,2 \
        | cut -f2-
    '';
  };
in
mkUserModule {
  name = "worktree";
  requires = [
    "git"
    "fish"
  ];
  parts = {
    pr = import ./pr.nix;
    linear = import ./linear.nix;
    stacked = import ./stacked.nix { inherit pkgs; };
    linear-stacked = import ./linear-stacked.nix;
  };
  home = {
    programs.fish = {
      functions = {
        # Namespace for branches the wt family invents (`git config wt.prefix`,
        # e.g. "fernando/"), so they can't collide with other people's PRs.
        # Empty when unset, which makes every call site a no-op by default.
        _wt_prefix = ''
          git config --default "" wt.prefix
        '';

        # Worktree/session name for a branch: drop our own prefix, then slashes
        # → dashes. "fernando/fix-foo" → "fix-foo", but someone else's
        # "alice/fix" stays "alice-fix" (whose branch it is still reads).
        _wt_name = ''
          string replace -r "^"(string escape --style=regex -- (_wt_prefix)) "" -- $argv[1] | string replace -a / -
        '';

        # Shared picker for every wt command that asks "which worktree?".
        # Takes the worktrees dir + a prompt word, prints the chosen name.
        #
        # Opens on the --fast rows (names + age, ~300ms), then swaps in the
        # dirty marks once the slow scan lands. reload-sync, not reload: the
        # first list stays on screen and searchable while that runs, instead
        # of blanking. Both passes emit the same columns, so the swap only
        # ever makes a `*` appear — and picking mid-swap is safe either way,
        # since the name is field 1 of both.
        _wt_pick = ''
          ${wt-rows}/bin/wt-rows --fast $argv[1] \
            | fzf --prompt="$argv[2]> " --height=40% \
                  --header="* = uncommitted changes (rm needs --force)" \
                  --bind "start:reload-sync(${wt-rows}/bin/wt-rows '$argv[1]')" \
            | string split -f1 ' '
        '';

        wt = ''
          set git_root (git rev-parse --show-toplevel 2>/dev/null)
          or begin; echo "wt: not a git repo"; return 1; end

          _git_clean_stale_lock

          set name $argv[1]
          set branch $argv[2]

          set main_root (git worktree list --porcelain | head -1 | string replace "worktree " "")
          set repo_name (basename $main_root)
          set wt_base (dirname $main_root)

          # No args: fzf to switch to existing worktree
          if test -z "$name"
            if not set -q TMUX
              echo "wt: not in tmux"
              return 1
            end

            set wt_dir "$wt_base/$repo_name.worktrees"
            if not test -d "$wt_dir"; or test (count (command ls "$wt_dir" 2>/dev/null)) -eq 0
              echo "wt: no worktrees found"
              return 1
            end

            set name (_wt_pick "$wt_dir" worktree)
            or return 1
          end

          set wt_path "$wt_base/$repo_name.worktrees/$name"

          if set -q TMUX
            # Use root session name (strip /suffix if called from a worktree session)
            set parent_session (command tmux display-message -p '#{session_name}' | string split -m 1 '/')[1]
            set session_name "$parent_session/$name"

            # Session already exists: just switch
            if command tmux has-session -t "=$session_name" 2>/dev/null
              command tmux switch-client -t "=$session_name"
              return 0
            end
          end

          # Create worktree if dir doesn't exist
          set -l is_new 0
          if not test -d "$wt_path"
            git fetch origin 2>/dev/null
            set base_branch (git rev-parse --abbrev-ref HEAD 2>/dev/null)
            if test -z "$base_branch" -o "$base_branch" = "HEAD"
              echo "wt: detached HEAD — checkout a branch first"
              return 1
            end

            # No branch given: name it after the worktree, namespaced by
            # wt.prefix so it can't collide with other people's PRs. An
            # explicit branch arg is used verbatim.
            test -z "$branch"; and set branch (_wt_prefix)"$name"

            # Use existing branch (local, then remote), else create it from current
            if git show-ref --verify --quiet "refs/heads/$branch"
              git worktree add "$wt_path" "$branch"
            else if git show-ref --verify --quiet "refs/remotes/origin/$branch"
              git worktree add --track -b "$branch" "$wt_path" "origin/$branch"
            else
              git worktree add -b "$branch" "$wt_path" "$base_branch"
            end
            or begin; echo "wt: failed to create worktree"; return 1; end
            echo "Created worktree at $wt_path (from $base_branch)"
            direnv allow "$wt_path" 2>/dev/null
            set is_new 1
          end

          # Create tmux session and switch
          if set -q TMUX
            command tmux new-session -d -s "$session_name" -c "$wt_path"

            # Run setup script for new worktrees
            if test $is_new -eq 1
              set -l setup_file "$wt_base/$repo_name.worktrees/.setup"
              if test -f "$setup_file"
                command tmux send-keys -t "=$session_name" "sh '$setup_file'" Enter
              end
            end

            command tmux switch-client -t "=$session_name"
          else
            echo "Not in tmux — run: cd $wt_path && opencode"
          end
        '';

        wtmv = ''
          set git_root (git rev-parse --show-toplevel 2>/dev/null)
          or begin; echo "wtmv: not a git repo"; return 1; end

          _git_clean_stale_lock

          set main_root (git worktree list --porcelain | head -1 | string replace "worktree " "")
          set repo_name (basename $main_root)
          set wt_base (dirname $main_root)
          set wt_dir "$wt_base/$repo_name.worktrees"

          set old $argv[1]
          set new $argv[2]

          # One arg in a worktree session: rename current worktree to that name
          if test -z "$new"; and set -q TMUX
            set -l current (command tmux display-message -p '#{session_name}')
            if string match -q '*/*' -- "$current"
              set new $old
              set old (string split -m 1 '/' -- "$current")[2]
            end
          end

          # No old name: fzf picker
          if test -z "$old"
            if not test -d "$wt_dir"; or test (count (command ls "$wt_dir" 2>/dev/null)) -eq 0
              echo "wtmv: no worktrees found"
              return 1
            end
            set old (_wt_pick "$wt_dir" rename)
            or return 1
          end

          # No new name: prompt for it
          if test -z "$new"
            read -P "wtmv: rename '$old' to: " new
            or return 1
          end

          if test -z "$new"
            echo "wtmv: new name required"
            return 1
          end

          if test "$old" = "$new"
            echo "wtmv: names are identical"
            return 1
          end

          set old_path "$wt_dir/$old"
          set new_path "$wt_dir/$new"

          if not test -d "$old_path"
            echo "wtmv: no worktree found for '$old'"
            return 1
          end
          if test -e "$new_path"
            echo "wtmv: '$new' already exists"
            return 1
          end

          # Capture branch before moving (to optionally rename it)
          set -l branch (git -C "$old_path" rev-parse --abbrev-ref HEAD 2>/dev/null)

          # Move the worktree — git updates its metadata + gitdir links.
          # Run from main_root so we're not inside the dir being moved.
          git -C "$main_root" worktree move "$old_path" "$new_path"
          or begin; echo "wtmv: failed to move worktree"; return 1; end

          # Rename the branch only when it matches the old worktree name
          # (the auto-named case from wt), fixing the typo everywhere.
          # wt.prefix is empty when unset, so this is the plain name by default.
          set -l prefix (_wt_prefix)
          if test "$branch" = "$prefix$old"
            git -C "$main_root" branch -m "$branch" "$prefix$new" 2>/dev/null
          end

          direnv allow "$new_path" 2>/dev/null

          # Rename the tmux session (parent/old -> parent/new)
          if set -q TMUX
            set -l old_session (command tmux list-sessions -F '#{session_name}' | grep "/$old\$" | head -1)
            if test -n "$old_session"
              set -l parent (string split -m 1 '/' -- "$old_session")[1]
              command tmux rename-session -t "=$old_session" "$parent/$new"
            end
          end

          echo "Renamed worktree '$old' → '$new'"
        '';

        wtls = "git worktree list $argv";

        wtrm = ''
          set git_root (git rev-parse --show-toplevel 2>/dev/null)
          or begin; echo "wtrm: not a git repo"; return 1; end

          set -l force 0
          set -l args
          for arg in $argv
            if test "$arg" = "--force" -o "$arg" = "-f"
              set force 1
            else
              set -a args $arg
            end
          end

          set name $args[1]

          set main_root (git worktree list --porcelain | head -1 | string replace "worktree " "")
          set repo_name (basename $main_root)
          set wt_base (dirname $main_root)

          # No arg: self-remove if in a worktree session, otherwise fzf picker
          set -l auto_name 0
          if test -z "$name"
            if set -q TMUX
              set -l current (command tmux display-message -p '#{session_name}')
              if string match -q '*/*' -- "$current"
                set name (string split -m 1 '/' -- "$current")[2]
                set auto_name 1
              end
            end
          end

          if test -z "$name"
            set wt_dir "$wt_base/$repo_name.worktrees"
            if not test -d "$wt_dir"; or test (count (command ls "$wt_dir" 2>/dev/null)) -eq 0
              echo "wtrm: no worktrees found"
              return 1
            end

            set name (_wt_pick "$wt_dir" remove)
            or return 1
          end

          # Guard: $wt_path gets rm -rf'd below, so no traversal in $name
          if string match -qr '(^\.|/)' -- "$name"
            echo "wtrm: invalid worktree name '$name'"
            return 1
          end

          set wt_path "$wt_base/$repo_name.worktrees/$name"

          # Resolve the branch so a half-deleted worktree still cleans up fully:
          # from the worktree itself, else from git's (possibly stale)
          # registration, else the name wt would have given it.
          set -l branch (git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null)
          if test -z "$branch" -o "$branch" = "HEAD"
            set branch (git worktree list --porcelain | awk -v p="$wt_path" '$1=="worktree"{m=($2==p)} m&&$1=="branch"{sub("refs/heads/","",$2); print $2; exit}')
          end
          test -n "$branch"; or set branch (_wt_prefix)"$name"
          git show-ref --verify --quiet "refs/heads/$branch"; or set branch ""

          # Already in the desired state: prune any stale registration and stop.
          # Removing something twice is not an error.
          if not test -e "$wt_path"; and test -z "$branch"
            git worktree prune
            echo "wtrm: '$name' already removed"
            return 0
          end

          # Confirm when name was auto-detected from session
          if test $auto_name -eq 1
            read -P "wtrm: remove worktree '$name'? [y/N] " confirm
            if not string match -qi 'y' -- "$confirm"
              return 0
            end
          end

          # Detect if we're removing our own session (self-remove)
          set -l self_rm 0
          set -l current_session ""
          set -l parent_session ""
          if set -q TMUX
            set current_session (command tmux display-message -p '#{session_name}')
            set -l target_session (command tmux list-sessions -F '#{session_name}' | grep "/$name\$" | head -1)
            if test -n "$target_session" -a "$current_session" = "$target_session"
              set self_rm 1
              set parent_session (string split -m 1 '/' -- "$current_session")[1]
            end
          end

          if test $self_rm -eq 1
            # Self-remove: need a session to return to
            if not command tmux has-session -t "=$parent_session" 2>/dev/null
              # Fall back to any other session
              set parent_session (command tmux list-sessions -F '#{session_name}' | grep -v "^$current_session\$" | head -1)
              if test -z "$parent_session"
                echo "wtrm: no other session to switch to"
                return 1
              end
            end

            # Pre-check for uncommitted changes (can't report errors after switching away)
            if test $force -eq 0
              if test -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)"
                echo "wtrm: worktree has uncommitted changes — use 'wtrm --force' to force"
                return 1
              end
            end

            # Build cleanup command (POSIX shell, runs server-side via tmux
            # run-shell -b). Every step tolerates already-being-done: --force is
            # safe here because the pre-check above cleared the worktree, and
            # rm -rf + prune reconcile a dir git no longer tracks (or vice versa).
            set -l cleanup "tmux kill-session -t '=$current_session'"
            set cleanup "$cleanup; git -C '$main_root' worktree remove --force '$wt_path' 2>/dev/null"
            set cleanup "$cleanup; rm -rf '$wt_path'"
            set cleanup "$cleanup; git -C '$main_root' worktree prune"
            if test -n "$branch"
              if test $force -eq 1
                set cleanup "$cleanup; git -C '$main_root' branch -D '$branch' 2>/dev/null"
              else
                set cleanup "$cleanup; git -C '$main_root' branch -d '$branch' 2>/dev/null"
              end
            end

            # Switch to parent, then schedule cleanup in background.
            # Silenced: run-shell displays stdout (and a failing exit status) in
            # view mode on whatever client is attached — git's "Deleted branch
            # X" would take over an unrelated session seconds later.
            command tmux switch-client -t "=$parent_session"
            command tmux run-shell -b "{ $cleanup; } >/dev/null || true"
          else
            # Regular remove (from a different session)
            if set -q TMUX
              set -l target_session (command tmux list-sessions -F '#{session_name}' | grep "/$name\$" | head -1)
              if test -n "$target_session"
                command tmux kill-session -t "=$target_session"
              end
            end

            # Refuse to throw away real work; anything else is fair game
            if test $force -eq 0; and test -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)"
              echo "wtrm: worktree has changes — use 'wtrm --force $name' to force"
              return 1
            end

            # Don't rm the floor out from under the shell
            if string match -q "$wt_path*" -- "$PWD"
              cd "$main_root"
            end

            # Teardown: each step tolerates already-being-done, so a dir git
            # forgot (or a registration whose dir vanished) still ends up gone.
            git worktree remove --force "$wt_path" 2>/dev/null
            rm -rf "$wt_path"
            git worktree prune

            if test -z "$branch"
              echo "Removed worktree '$name'"
            else if test $force -eq 1
              git branch -D "$branch" 2>/dev/null
              echo "Removed worktree '$name' and branch '$branch'"
            else if git branch -d "$branch" 2>/dev/null
              echo "Removed worktree '$name' and branch '$branch'"
            else
              echo "Removed worktree '$name' (branch '$branch' not fully merged — use 'wtrm --force $name' to force)"
            end
          end
        '';
      };

      shellInit = ''
        # Completion for wt: 1st arg = existing worktree names, 2nd arg = branches
        complete -f -c wt -n "test (count (commandline -opc)) -eq 1" -a '(
          set -l mr (git worktree list --porcelain 2>/dev/null | head -1 | string replace "worktree " "")
          set -l rn (basename $mr 2>/dev/null)
          set -l wd (dirname $mr 2>/dev/null)/$rn.worktrees
          test -d $wd 2>/dev/null; and command ls $wd 2>/dev/null
        )'
        complete -f -c wt -n "test (count (commandline -opc)) -eq 2" -a '(git branch -a --format="%(refname:short)" 2>/dev/null | string replace -r "^origin/" "" | sort -u | grep -v "^HEAD")'

        # Completion for wtmv: 1st arg = existing worktree names
        complete -f -c wtmv -n "test (count (commandline -opc)) -eq 1" -a '(
          set -l mr (git worktree list --porcelain 2>/dev/null | head -1 | string replace "worktree " "")
          set -l rn (basename $mr 2>/dev/null)
          set -l wd (dirname $mr 2>/dev/null)/$rn.worktrees
          test -d $wd 2>/dev/null; and command ls $wd 2>/dev/null
        )'

        # Completion for wtrm: existing worktree names + --force flag
        complete -f -c wtrm -l force -s f -d "Force remove even with uncommitted changes"
        complete -f -c wtrm -a '(
          set -l mr (git worktree list --porcelain 2>/dev/null | head -1 | string replace "worktree " "")
          set -l rn (basename $mr 2>/dev/null)
          set -l wd (dirname $mr 2>/dev/null)/$rn.worktrees
          test -d $wd 2>/dev/null; and command ls $wd 2>/dev/null
        )'
      '';
    };
  };
}
