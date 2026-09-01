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

  # Everything slow about making a worktree — fetch, checkout, .setup — in one
  # script, so `wt` can hand it to `tmux run-shell -b` and return. The caller
  # has already switched you into the new session by then; none of this ever
  # touches your shell, your history, or your scrollback.
  #
  # Output goes to a log rather than the terminal because run-shell has no
  # terminal: with -b it's detached, and anything it prints would otherwise be
  # dumped into view mode over whatever session you're looking at.
  wt-create = pkgs.writeShellApplication {
    name = "wt-create";
    runtimeInputs = [
      pkgs.git
      pkgs.direnv
      # run-shell inherits the tmux server's PATH — roughly tmux + /usr/bin +
      # /bin, no ~/.nix-profile — so an LFS repo checked out from here can't
      # find git-lfs for its post-checkout hook and warns on every create.
      # (The filters themselves are configured as absolute store paths, so
      # content is unaffected; this is about the hook and its bookkeeping.)
      pkgs.git-lfs
    ];
    text = ''
      # usage: wt-create <main_root> <wt_path> <branch> <base_branch>
      #
      # Checkout only. .setup deliberately does not run here — it needs a login
      # shell and a direnv-loaded environment, and the honest way to get both
      # is a real tmux window, which wt-enter opens. Reproducing that
      # environment by hand from a run-shell context meant stacking `sh -l -c`
      # around `direnv exec` and still missing /usr/local/bin.
      main_root="$1"
      wt_path="$2"
      branch="$3"
      base_branch="$4"

      name="''${wt_path##*/}"
      # Beside .setup, never inside the worktree: a file in there would be an
      # untracked change and would light up the `*` marker in every picker.
      log="''${wt_path%/*}/.$name.log"

      # tmux is deliberately not in runtimeInputs. run-shell inherits the tmux
      # server's PATH, so a bare `tmux` is guaranteed to be the same binary as
      # the running server — pinning our own could mean a protocol mismatch.
      # (wtrm's background cleanup already relies on this.)
      fail() {
        tmux display-message "wt: $name — $1 failed, see $log" 2>/dev/null || true
        exit 1
      }

      # Keep the terminal when there is one. wt-enter runs this in the pane you
      # are staring at, the checkout can take 37s on monobloco depending on how
      # much the fetch has to pull, and git only draws its "Updating files"
      # progress onto a tty — teeing would silence it, since a pipe reads as
      # non-interactive. Silence for half a minute looks hung.
      #
      # With no tty (tmux run-shell -b) everything goes to the log instead,
      # which is also what stops run-shell dumping git output in view mode over
      # whatever unrelated session happens to be attached. Append, because a
      # retry and the two-phase sync path both run this twice; the date header
      # separates the runs.
      [ -t 1 ] || exec >>"$log" 2>&1
      echo "=== $(date): $wt_path on $branch (from $base_branch) ==="

      # Idempotent, which is what lets `wt` split this into a synchronous
      # checkout followed by a background setup: the second call finds the
      # worktree already registered and falls straight through to .setup.
      if [ -e "$wt_path/.git" ]; then
        echo "worktree already present, skipping add"
      else

      # Use existing branch (local, then remote), else create it from base.
      #
      # The local check goes first so it can answer without the network.
      # `git fetch origin` costs ~2.7s against a big repo and the only thing it
      # feeds is the refs/remotes lookup below — so it's pure latency once a
      # local branch has already matched, which is every time you re-create a
      # worktree you deleted.
      #
      # Each `add` targets a directory `wt` already created, so it can start
      # the session there. git takes over an empty dir happily.
      if git -C "$main_root" show-ref --verify --quiet "refs/heads/$branch"; then
        git -C "$main_root" worktree add "$wt_path" "$branch" || fail "worktree add"
      else
        # No local branch, so the remote's answer decides — but read from the
        # refs/remotes we already have rather than fetching for them.
        #
        # The fetch used to live here and it was the single biggest cost in
        # `wt`: 2839ms idle and the reason the whole build ranged 9-37s, since
        # the checkout itself is a steady ~5s. It moved to wt-pool-fill, which
        # runs detached after every `wt`. Narrowing it was measured and does not
        # help — a single-branch ls-remote is 2434ms against 2839ms for the lot,
        # because round-trip time dominates. Only removing it does.
        #
        # The trade: refs/remotes are as fresh as your last `wt` here, so a
        # branch pushed from another machine since then is invisible and you
        # would fork a second one with the same name.
        if git -C "$main_root" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
          git -C "$main_root" worktree add --track -b "$branch" "$wt_path" "origin/$branch" || fail "worktree add"
        else
          git -C "$main_root" worktree add -b "$branch" "$wt_path" "$base_branch" || fail "worktree add"
        fi
      fi

      direnv allow "$wt_path" || true
      fi

      echo "=== $(date): done ==="
    '';
  };

  # Claim a pre-built worktree from the pool instead of checking out 41882
  # files again. Exits 0 when it hands back a ready worktree at $wt_path, and 1
  # when the caller should build one the slow way — so every path through this
  # is optional and a missing or broken pool just costs what it always cost.
  #
  # Measured on monobloco:
  #   build from scratch                        4778ms
  #   claim: git worktree move                    28ms
  #   claim: git checkout -b (slot at base)      375ms
  #
  # Staleness turned out not to matter, which is why nothing here refreshes
  # slots on a timer: git only writes the diff, so a slot 200 commits and 2891
  # files behind still claims in 738ms. Age is a disk concern, not a speed one,
  # and wt-pool-fill handles it.
  wt-claim = pkgs.writeShellApplication {
    name = "wt-claim";
    runtimeInputs = [
      pkgs.git
      pkgs.direnv
      pkgs.git-lfs
    ];
    text = ''
      # usage: wt-claim <main_root> <wt_path> <branch> <base_branch>
      main_root="$1"
      wt_path="$2"
      branch="$3"
      base_branch="$4"

      pool="''${wt_path%/*}/.pool"
      name="''${wt_path##*/}"
      log="''${wt_path%/*}/.$name.log"

      [ -d "$pool" ] || exit 1

      for slot in "$pool"/*/; do
        slot="''${slot%/}"
        # Unexpanded glob when the pool is empty.
        [ -d "$slot" ] || continue
        # `.git` is a file in a linked worktree; a bare directory is a slot
        # whose build died half way and is not safe to hand out.
        [ -e "$slot/.git" ] || continue

        # Never claim a slot something has touched — those changes would ride
        # along into your new worktree and look like your own work.
        [ -n "$(git --no-optional-locks -C "$slot" status --porcelain 2>/dev/null)" ] && continue

        # The rename *is* the claim, and it is atomic. Two concurrent `wt`s
        # cannot both win: the loser's move fails, it falls through this loop
        # and builds normally. That is the whole concurrency story — no lock.
        git -C "$main_root" worktree move "$slot" "$wt_path" >>"$log" 2>&1 || continue

        {
          echo "=== $(date): claimed $slot -> $wt_path on $branch ==="

          # Same branch resolution as a fresh build, minus the fetch. The
          # refs/remotes we read here are kept warm by wt-pool-fill, which
          # fetches in the background after every wt — that is what keeps a
          # network round trip off this path.
          if git -C "$main_root" show-ref --verify --quiet "refs/heads/$branch"; then
            git -C "$wt_path" checkout "$branch"
          elif git -C "$main_root" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
            git -C "$wt_path" checkout -b "$branch" --track "origin/$branch"
          else
            git -C "$wt_path" checkout -b "$branch" "$base_branch"
          fi
        } >>"$log" 2>&1 || {
          # Claimed but unusable. Returning 1 alone would strand a worktree at
          # $wt_path on the wrong branch, and the caller would trust it because
          # .git exists — so tear it down and let the slow path build clean.
          git -C "$main_root" worktree remove --force "$wt_path" >>"$log" 2>&1 || true
          rm -rf "''${wt_path:?}"
          exit 1
        }

        direnv allow "$wt_path" >>"$log" 2>&1 || true
        exit 0
      done

      exit 1
    '';
  };

  # Keeps the pool stocked and does the one network round trip, both off the
  # critical path: `wt` fires this detached after it has already switched you.
  #
  # Filling on use rather than on a schedule is deliberate — a repo you never
  # `wt` in never gets a slot, so the disk cost follows what you actually work
  # on. The first `wt` in a repo pays full price and leaves a slot behind; every
  # one after it claims in ~400ms.
  wt-pool-fill = pkgs.writeShellApplication {
    name = "wt-pool-fill";
    runtimeInputs = [
      pkgs.git
      pkgs.git-lfs
    ];
    text = ''
      # usage: wt-pool-fill <main_root>
      main_root="$1"

      wd="$(dirname "$main_root")/$(basename "$main_root").worktrees"
      pool="$wd/.pool"
      target=1
      max_age_days=14
      registry="''${XDG_STATE_HOME:-$HOME/.local/state}/wt/pools"

      mkdir -p "$pool"
      exec >>"$pool/.fill.log" 2>&1
      echo "=== $(date): fill $pool ==="

      # Stamp first: this is "when was this repo last worked in", and the prune
      # below reads it. Touching it here means any `wt` counts as activity.
      touch "$pool/.last-used"

      mkdir -p "''${registry%/*}"
      grep -qxF "$pool" "$registry" 2>/dev/null || echo "$pool" >>"$registry"

      # Prune every pool we know of, not just this one. Without this a repo you
      # stop touching keeps its slot (1.1G on monobloco) forever, because the
      # only thing that ever runs is `wt`, and you are by definition not running
      # it there. Doing it from whichever repo you *are* in costs nothing.
      if [ -f "$registry" ]; then
        # Snapshot before iterating: the loop rewrites the registry, and
        # reading a file while rewriting it is how entries go missing.
        mapfile -t pools < "$registry"
        kept=()
        for p in ''${pools[@]+"''${pools[@]}"}; do
          [ -n "$p" ] || continue
          # Pool directory gone (repo deleted or moved): drop the entry.
          [ -d "$p" ] || continue
          kept+=("$p")
          [ "$p" = "$pool" ] && continue
          # A stamp older than the window — or missing entirely — is stale.
          [ -n "$(find "$p/.last-used" -mtime "-$max_age_days" 2>/dev/null)" ] && continue

          echo "pruning stale pool $p"
          root="''${p%.worktrees/.pool}"
          for s in "$p"/*/; do
            [ -d "$s" ] || continue
            git -C "$root" worktree remove --force "''${s%/}" 2>/dev/null || true
            rm -rf "''${s%/}"
          done
          git -C "$root" worktree prune 2>/dev/null || true
        done
        printf '%s\n' ''${kept[@]+"''${kept[@]}"} > "$registry"
      fi

      # The deferred round trip. `wt` no longer fetches, so this is the only
      # thing keeping refs/remotes fresh — which means your remote view is as
      # current as your last `wt` in this repo.
      git -C "$main_root" fetch origin || true

      count=$(find "$pool" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
      [ "$count" -ge "$target" ] && { echo "pool has $count, target $target"; exit 0; }

      # Park slots at whatever the main worktree is on, since that is what `wt`
      # branches from. Detached, so the pool never shows up in `git branch`.
      base=$(git -C "$main_root" rev-parse HEAD)
      while [ "$count" -lt "$target" ]; do
        slot="$pool/slot-$(date +%s)-$-$count"
        git -C "$main_root" worktree add --detach "$slot" "$base" || break
        count=$((count + 1))
      done
      echo "=== $(date): pool now $count ==="
    '';
  };

  # The new session's first process. It builds the worktree and then *becomes*
  # your shell in it, which is what lets `wt` switch you over instantly without
  # ever handing you a prompt in a directory that isn't a worktree yet.
  #
  # The alternative shapes both cost something this doesn't:
  #   - build first, then switch: your old shell blocks ~9s on monobloco, and
  #     the switch lands whenever it finishes — the surprise jump.
  #   - switch first, prompt immediately: the prompt is live in a bare
  #     directory for those 9s, where git and anything you type see nothing.
  # Here the wait is in the session you are going to work in, and it is visibly
  # a wait rather than a lie.
  wt-enter = pkgs.writeShellApplication {
    name = "wt-enter";
    runtimeInputs = [ wt-create ];
    text = ''
      # usage: wt-enter <main_root> <wt_path> <branch> <base_branch> <session> [setup_file]
      main_root="$1"
      wt_path="$2"
      branch="$3"
      base_branch="$4"
      session="$5"
      setup_file="''${6:-}"

      name="''${wt_path##*/}"

      # default-*command*, not default-shell. This config deliberately pins
      # default-shell to /bin/sh because that is the wrapper tmux execs for
      # run-shell, if-shell and display-popup -E; reading it here lands you in
      # macOS bash instead of fish. default-command is what tmux actually runs
      # for a new interactive pane, login flag included — taking it verbatim
      # means these panes stay identical to every other pane for free.
      cmd="$(tmux show-options -gv default-command 2>/dev/null || true)"
      # Login shell in the fallback too: overriding a pane's command opts out
      # of the login shell tmux would otherwise give it, and the tmux server's
      # own PATH is barely more than /usr/bin.
      [ -n "$cmd" ] || cmd="''${SHELL:-/bin/sh} -l"

      if [ ! -e "$wt_path/.git" ]; then
        printf 'wt: building %s…\n' "$name"
        if wt-create "$main_root" "$wt_path" "$branch" "$base_branch"; then
          # Wipe screen + scrollback, so what you land on is a clean prompt
          # rather than build noise. ANSI rather than `clear`, which would be
          # one more thing to find on that thin PATH.
          printf '\033[H\033[2J\033[3J'
        else
          # No log reference: wt-create writes to this terminal when it has
          # one, so git's own error is already on screen above.
          printf '\nwt: build failed — see the error above.\n\n'
          exec sh -c "exec $cmd"
        fi
      fi

      # .setup gets its own detached window rather than a run-shell job, and
      # the window is the point: tmux starts it as a login shell in the
      # worktree, so path_helper contributes /usr/local/bin (where OrbStack's
      # docker symlink lives) and direnv loads the dev shell on its first
      # prompt. That is exactly the environment a .setup author tested against.
      # Handing the same script to run-shell instead means reconstructing both
      # halves by hand, which is how `make setup` ended up dying on
      # _check-docker while the identical script worked when run manually.
      #
      # -d so it never steals focus; you land on window 0 either way.
      if [ -n "$setup_file" ] && [ -f "$setup_file" ]; then
        win=$(tmux new-window -d -t "=$session:" -n wt-setup -c "$wt_path" \
                -P -F '#{window_id}' 2>/dev/null || true)
        if [ -n "$win" ]; then
          # fish `; and exit`: the window closes itself when setup succeeds and
          # stays open, error on screen, when it doesn't. Verified against
          # remain-on-exit=off, which is the global default here.
          #
          # `sh -e` because plain sh reports only the last line's status, and
          # these scripts are several independent commands — without it a setup
          # that dies on line 1 still looks like it worked, and the window
          # would helpfully close over the evidence.
          #
          # The leading space is load-bearing: fish omits space-prefixed
          # commands from history, and fish history is global, so without it
          # every `wt` would leave this line in the history of every shell.
          tmux send-keys -t "$win" " sh -e '$setup_file'; and exit" Enter
        fi
      fi

      # `exec` inside too, so sh replaces itself rather than lingering as a
      # parent of your shell.
      exec sh -c "exec $cmd"
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

          # `.git` — a *file* in a linked worktree — not the directory, which
          # `wt` now creates itself before the checkout so the new session can
          # start inside it. On `test -d` an empty dir left by a failed run
          # would read as "already there" and wedge you in a broken session.
          set -l is_new 0
          not test -e "$wt_path/.git"; and set is_new 1

          set -l setup_file "$wt_base/$repo_name.worktrees/.setup"
          test -f "$setup_file"; or set setup_file ""

          # Resolve the branch up front. These are local and instant, and they
          # have to fail *before* a session exists — an error is useless once
          # we've switched away from the shell that would print it.
          if test $is_new -eq 1
            set base_branch (git rev-parse --abbrev-ref HEAD 2>/dev/null)
            if test -z "$base_branch" -o "$base_branch" = "HEAD"
              echo "wt: detached HEAD — checkout a branch first"
              return 1
            end

            # No branch given: name it after the worktree, namespaced by
            # wt.prefix so it can't collide with other people's PRs. An
            # explicit branch arg is used verbatim.
            test -z "$branch"; and set branch (_wt_prefix)"$name"
          end

          if not set -q TMUX
            # Nothing to background onto without tmux, so just do it and say
            # where the output went.
            test $is_new -eq 1; and begin
              mkdir -p "$wt_path"
              echo "wt: building $name (log: $wt_base/$repo_name.worktrees/.$name.log)"
              ${wt-create}/bin/wt-create "$main_root" "$wt_path" "$branch" "$base_branch" "$setup_file"
              or return 1
            end
            echo "Not in tmux — run: cd $wt_path && opencode"
            return 0
          end

          # Use root session name (strip /suffix if called from a worktree session)
          set parent_session (command tmux display-message -p '#{session_name}' | string split -m 1 '/')[1]
          set session_name "$parent_session/$name"

          # Nothing to build: just switch. The is_new check is load-bearing now
          # that the session is created *before* the worktree — on has-session
          # alone, one failed `git worktree add` would leave a session that
          # `wt $name` switches into forever, never retrying. Falling through
          # instead re-runs the creation into the session that's already there.
          if test $is_new -eq 0; and command tmux has-session -t "=$session_name" 2>/dev/null
            command tmux switch-client -t "=$session_name"
            return 0
          end

          # Try the pool before anything else. A claim is ~400ms against 4778ms
          # to build, which is cheap enough to do synchronously right here —
          # and doing it synchronously is the point: the session below then
          # starts in a worktree that is already real, so wt-enter has nothing
          # to build and you get a prompt immediately rather than watching a
          # checkout. An empty or unusable pool just exits 1 and costs nothing.
          if test $is_new -eq 1
            ${wt-claim}/bin/wt-claim "$main_root" "$wt_path" "$branch" "$base_branch"
          end

          # tmux needs the -c to exist to start a pane there, and `git worktree
          # add` is happy to take over an empty directory, so this costs
          # nothing and lets the session be created before the checkout is.
          # A claim will have created it already; this covers the miss.
          mkdir -p "$wt_path"

          # WT_SYNC is for callers that touch the worktree the instant `wt`
          # returns — wtoc moves an opencode session into it, and with -c
          # patches it. Building here, before the session exists, both gives
          # them a finished worktree and keeps this from racing the identical
          # build wt-enter would start. wt-create is idempotent, so wt-enter
          # then finds it done and goes straight to the prompt.
          #
          # The setup file is deliberately empty: WT_SYNC waits for the
          # checkout, never for `pnpm i`.
          if test $is_new -eq 1; and set -q WT_SYNC
            ${wt-create}/bin/wt-create "$main_root" "$wt_path" "$branch" "$base_branch"
            or return 1
          end

          # Only hand wt-enter a setup file for a worktree we're creating —
          # otherwise merely reopening a session would re-run `pnpm i`.
          set -l enter_setup ""
          test $is_new -eq 1; and set enter_setup "$setup_file"

          if command tmux has-session -t "=$session_name" 2>/dev/null
            # Session outlived its worktree (a failed build, or wtrm racing).
            # There's no pane command to hand the build to, so detach it —
            # checkout only, since .setup needs a window wt-enter would have
            # opened. Rare enough to leave: `wtrm` then `wt` re-runs it fully.
            test $is_new -eq 1; and command tmux run-shell -b \
              "'${wt-create}/bin/wt-create' '$main_root' '$wt_path' '$branch' '$base_branch'"
          else
            command tmux new-session -d -s "$session_name" -c "$wt_path" \
              "'${wt-enter}/bin/wt-enter' '$main_root' '$wt_path' '$branch' '$base_branch' '$session_name' '$enter_setup'"
          end

          command tmux switch-client -t "=$session_name"

          # Restock and fetch, detached, after you have already been switched.
          # Unconditional: it is also what keeps refs/remotes warm for the next
          # `wt`, prunes pools for repos you have stopped using, and rebuilds a
          # slot this run just consumed.
          command tmux run-shell -b "'${wt-pool-fill}/bin/wt-pool-fill' '$main_root'"
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
