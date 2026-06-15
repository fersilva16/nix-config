# worktree stacked part — stacked worktrees via av (Aviator). A stack is a tree
# of branches, each living in its own sandboxed worktree. av tracks the parent
# of each branch (shared metadata in the common git dir), so PRs target their
# parent and a fix on an upstream branch can cascade-rebase the downstream
# worktrees. Cross-worktree restack is driven by path with `av -C <path>` so
# each sandbox is rebased in place.
{ pkgs }:
{
  home =
    { lib, userCfg, ... }:
    lib.mkIf userCfg.av.enable {
      # jq: used by wts land / _wts_pick_session to read av.db metadata.
      home.packages = [ pkgs.jq ];

      programs.fish = {
        functions = {
          wts = ''
            set -l sub $argv[1]
            set -e argv[1]

            set -l main_root (git worktree list --porcelain 2>/dev/null | head -1 | string replace "worktree " "")
            if test -z "$main_root"
              echo "wts: not a git repo" >&2
              return 1
            end
            set -l repo_name (basename $main_root)
            set -l wt_base (dirname $main_root)

            switch "$sub"
              case "" tree
                av tree $argv

              case fork
                # wts fork <name> [branch] — child worktree stacked on current branch
                set -l name $argv[1]
                if test -z "$name"
                  echo "wts fork: usage: wts fork <name> [branch]" >&2
                  return 1
                end
                set -l parent (git rev-parse --abbrev-ref HEAD 2>/dev/null)
                if test -z "$parent" -o "$parent" = HEAD
                  echo "wts fork: detached HEAD — checkout the parent branch first" >&2
                  return 1
                end
                set -l branch $argv[2]
                test -z "$branch"; and set branch $name
                set -l wt_path "$wt_base/$repo_name.worktrees/$name"

                # Create the stacked worktree+branch off the current (parent) branch.
                wt $name $branch
                or return 1

                # Register the stack edge so PRs target the parent. Adopt needs
                # at least one commit; on an empty fork it's a no-op until the
                # first commit, so don't treat failure as fatal.
                if not av -C "$wt_path" adopt --parent "$parent" 2>/dev/null
                  echo "wts: '$branch' forked from '$parent'. After your first commit, run 'wts adopt $parent' to register the stack." >&2
                end

              case adopt
                # wts adopt [parent] — register current branch as a child of <parent>
                set -l parent $argv[1]
                if test -z "$parent"
                  set -l cur (git rev-parse --abbrev-ref HEAD 2>/dev/null)
                  set parent (git branch --format='%(refname:short)' | grep -v "^$cur\$" | fzf --prompt="parent> " --height=40%)
                  or return 1
                end
                av adopt --parent "$parent"

              case restack
                # Rebase the current branch onto its parent, then cascade into
                # descendant worktrees so each sandbox is restacked onto its
                # freshly-updated upstream.
                #
                # Descendants are discovered from av's STRUCTURAL parent edges
                # (av.db), not git content-ancestry. The old approach probed
                # `git merge-base --is-ancestor <cur-tip> <branch>`, which breaks
                # the moment you commit on the current branch: its children no
                # longer contain its tip, so they'd be silently skipped and the
                # worktrees left stale (while `av pr --all` had already pushed the
                # rebased versions to the remote — leaving local out of sync).
                set -l cur (git rev-parse --abbrev-ref HEAD 2>/dev/null)
                if test -z "$cur" -o "$cur" = HEAD
                  echo "wts restack: detached HEAD" >&2
                  return 1
                end

                set -l avdb (git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/av/av.db
                if not test -f "$avdb"
                  echo "wts restack: no av metadata — run 'wts init' + adopt first" >&2
                  return 1
                end

                av restack --current
                or begin
                  echo "wts restack: conflict in '$cur' — resolve, then 'av restack --continue'" >&2
                  return 1
                end

                # Transitive descendants of cur in BFS (ancestors-first) order,
                # walking av.db's child->parent edges so every parent is restacked
                # before its children. Each branch has exactly one parent, so the
                # walk visits each descendant once.
                set -l pairs (jq -r '.branches[] | "\(.name)|\(.parent.name // "")"' "$avdb")
                set -l descendants
                set -l frontier $cur
                while test (count $frontier) -gt 0
                  set -l next
                  for pair in $pairs
                    set -l np (string split "|" -- $pair)
                    if contains -- $np[2] $frontier
                      set -a descendants $np[1]
                      set -a next $np[1]
                    end
                  end
                  set frontier $next
                end

                # branch -> worktree path map
                set -l wtbranches
                set -l wtpaths
                set -l p ""
                for line in (git worktree list --porcelain)
                  set -l kv (string split -m 1 " " -- $line)
                  switch $kv[1]
                    case worktree
                      set p $kv[2]
                    case branch
                      set -a wtbranches (string replace "refs/heads/" "" -- $kv[2])
                      set -a wtpaths $p
                  end
                end

                for br in $descendants
                  set -l idx (contains -i -- $br $wtbranches)
                  if test -z "$idx"
                    echo "wts restack: '$br' has no worktree — restack it where it lives" >&2
                    continue
                  end
                  set -l path $wtpaths[$idx]
                  if test -n "$(git -C "$path" status --porcelain 2>/dev/null)"
                    echo "wts restack: '$br' has uncommitted changes — skipped (restack it manually)" >&2
                    continue
                  end
                  echo "↻ restacking $br"
                  av -C "$path" restack --current
                  or begin
                    echo "wts restack: conflict in '$br' ($path). Resolve there, then 'av -C $path restack --continue'." >&2
                    return 1
                  end
                end
                echo "✓ stack restacked"

              case sync
                # Restack the whole stack across worktrees, then push + retarget
                # every PR to its correct base. `av pr --all` pushes and fixes
                # bases without rebasing checked-out branches, so it's safe to
                # run once from the current worktree after the cascade.
                wts restack
                or return 1
                av pr --all $argv

              case pr
                # Create/update stacked PRs (each targeting its parent).
                av pr --all $argv

              case rm
                # Untrack from av + remove the worktree. Refuses if the branch
                # has stacked children, to avoid orphaning them — reparent first.
                set -l name $argv[1]
                set -l target_path (git rev-parse --show-toplevel 2>/dev/null)
                set -l target_branch (git rev-parse --abbrev-ref HEAD 2>/dev/null)
                if test -n "$name"
                  set target_path "$wt_base/$repo_name.worktrees/$name"
                  set target_branch (git -C "$target_path" rev-parse --abbrev-ref HEAD 2>/dev/null)
                end
                set -l target_tip (git -C "$target_path" rev-parse HEAD 2>/dev/null)

                set -l kids
                set -l p ""
                for line in (git worktree list --porcelain)
                  set -l kv (string split -m 1 " " -- $line)
                  switch $kv[1]
                    case branch
                      set -l b (string replace "refs/heads/" "" -- $kv[2])
                      if test "$b" != "$target_branch"; and git merge-base --is-ancestor $target_tip "$b" 2>/dev/null
                        set -a kids $b
                      end
                  end
                end
                if test (count $kids) -gt 0
                  echo "wts rm: '$target_branch' has stacked children: $kids" >&2
                  echo "Reparent them first — in each child worktree: av reparent --parent=<new>" >&2
                  echo "Then re-run: wts rm $name" >&2
                  return 1
                end

                av -C "$target_path" orphan 2>/dev/null
                wtrm $argv

              case init
                # One-time per repo: initialise av metadata (needs a GitHub PAT),
                # then pin av.trunk to origin's default branch so a global
                # init.defaultBranch that differs from this repo's trunk
                # (e.g. main vs prod) can't mis-root stacks.
                av init $argv
                or return 1
                set -l def (git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | string replace "refs/remotes/origin/" "")
                if test -z "$def"
                  set def (gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null)
                end
                if test -n "$def"
                  git config av.trunk "$def"
                  echo "wts init: av.trunk pinned to '$def'"
                end

              case land
                # Land the bottom PR of the current stack (stacks merge
                # bottom-up): merge into trunk, delete the remote branch so
                # GitHub retargets child PRs onto trunk, then sync each
                # descendant in its own worktree and remove the merged one.
                set -l avdb (git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/av/av.db
                if not test -f "$avdb"
                  echo "wts land: no av metadata — run 'wts init' + adopt first" >&2
                  return 1
                end
                set -l cur (git rev-parse --abbrev-ref HEAD 2>/dev/null)
                if test -z "$cur" -o "$cur" = HEAD
                  echo "wts land: run from a stack worktree" >&2
                  return 1
                end

                # Walk down to the stack bottom (branch whose parent is trunk).
                set -l bottom $cur
                set -l hops 0
                while true
                  set -l ptrunk (jq -r --arg b "$bottom" '.branches[$b].parent.trunk // empty' "$avdb")
                  test "$ptrunk" = true; and break
                  set -l parent (jq -r --arg b "$bottom" '.branches[$b].parent.name // empty' "$avdb")
                  if test -z "$parent"
                    echo "wts land: '$bottom' is not av-tracked — wts adopt first" >&2
                    return 1
                  end
                  set bottom $parent
                  set hops (math $hops + 1)
                  if test $hops -gt 20
                    echo "wts land: parent chain too deep — metadata cycle?" >&2
                    return 1
                  end
                end

                set -l prnum (jq -r --arg b "$bottom" '.branches[$b].pullRequest.number // empty' "$avdb")
                if test -z "$prnum"
                  echo "wts land: '$bottom' has no PR — run 'wts pr' first" >&2
                  return 1
                end

                echo "Landing stack bottom: $bottom (PR #$prnum)"
                read -P "Merge PR #$prnum into trunk? [y/N] " ok
                string match -qi y -- "$ok"; or return 1

                gh pr merge $prnum -s --admin $argv
                or begin; echo "wts land: merge failed" >&2; return 1; end

                # Deleting the remote branch makes GitHub retarget child PRs
                # onto the merged PR's base (trunk) automatically.
                git push origin --delete "$bottom" 2>/dev/null
                git -C "$main_root" pull 2>/dev/null

                # Descendants of bottom in ancestry order (BFS over av.db).
                set -l pairs (jq -r '.branches[] | "\(.name)|\(.parent.name)"' "$avdb")
                set -l ordered
                set -l frontier $bottom
                while test (count $frontier) -gt 0
                  set -l next
                  for pair in $pairs
                    set -l np (string split "|" -- $pair)
                    if contains -- $np[2] $frontier
                      set -a ordered $np[1]
                      set -a next $np[1]
                    end
                  end
                  set frontier $next
                end

                # branch -> worktree path map
                set -l wtbranches
                set -l wtpaths
                set -l p ""
                for line in (git worktree list --porcelain)
                  set -l kv (string split -m 1 " " -- $line)
                  switch $kv[1]
                    case worktree
                      set p $kv[2]
                    case branch
                      set -a wtbranches (string replace "refs/heads/" "" -- $kv[2])
                      set -a wtpaths $p
                  end
                end

                for b in $ordered
                  set -l idx (contains -i -- $b $wtbranches)
                  if test -z "$idx"
                    echo "wts land: '$b' has no worktree — sync it manually later" >&2
                    continue
                  end
                  echo "↻ syncing $b"
                  av -C "$wtpaths[$idx]" sync --push=yes --prune=no
                  or begin
                    echo "wts land: conflict in '$b'. Resolve there, then 'av -C $wtpaths[$idx] sync --continue'." >&2
                    return 1
                  end
                end

                # Remove the merged worktree last: if we ARE the bottom
                # worktree, wtrm self-removes and this shell dies with it.
                set -l idx (contains -i -- $bottom $wtbranches)
                if test -n "$idx"
                  echo "✓ landed PR #$prnum — removing worktree (run 'wts sync' later to prune metadata)"
                  wtrm --force (basename $wtpaths[$idx])
                else
                  git -C "$main_root" branch -D $bottom 2>/dev/null
                  echo "✓ landed PR #$prnum (run 'wts sync' later to prune metadata)"
                end

              case sessions
                _wts_pick_session

              case help -h --help
                echo "wts — stacked worktrees (av)" >&2
                echo "" >&2
                echo "worktree-aware commands:" >&2
                echo "  wts fork <name> [branch]  fork a child worktree stacked on current branch" >&2
                echo "  wts adopt [parent]        register current branch as a child of <parent>" >&2
                echo "  wts tree                  show the stack tree (default)" >&2
                echo "  wts restack               rebase downstream worktrees onto fixed upstreams" >&2
                echo "  wts sync                  restack + push + retarget PRs" >&2
                echo "  wts pr                    create/update stacked PRs" >&2
                echo "  wts rm [name]             untrack + remove a worktree (refuses if it has children)" >&2
                echo "  wts init                  initialise av metadata for this repo (one-time)" >&2
                echo "  wts land                  merge the stack's bottom PR, retarget + restack the rest" >&2
                echo "  wts sessions              stack-aware tmux session picker" >&2
                echo "" >&2
                echo "anything else is passed straight through to av in the current worktree," >&2
                echo "e.g. 'wts next', 'wts prev', 'wts switch', 'wts log', 'wts reparent'." >&2
                echo "See 'av --help' for the full list." >&2

              case '*'
                # Passthrough: any unrecognised subcommand goes straight to av,
                # operating on the current worktree. Keeps everything under one
                # entrypoint without reimplementing av's command surface.
                av $sub $argv
            end
          '';

          # Stack-aware tmux session picker: lists sessions with their branch
          # and stack depth (from av metadata), fzf to switch. Bound to
          # prefix+s (see programs.tmux.extraConfig below) and `wts sessions`.
          _wts_pick_session = ''
            if not set -q TMUX
              echo "wts sessions: requires tmux" >&2
              return 1
            end
            # Stream rows into fzf so the picker opens instantly (rows fill in
            # as they are computed). One jq per unique av.db, cached in-memory;
            # depth walks are pure string ops afterwards.
            set -l choice (
              begin
                set -l dbs
                set -l edges
                for line in (command tmux list-sessions -F "#{session_name}|#{session_path}" | sort -t "|" -k1,1)
                  set -l parts (string split "|" -- $line)
                  set -l name $parts[1]
                  set -l path $parts[2]
                  test "$name" = pocket; and continue
                  set -l label ""
                  set -l branch (git -C "$path" branch --show-current 2>/dev/null)
                  if test -n "$branch"
                    set label $branch
                    set -l avdb (git -C "$path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/av/av.db
                    if test -f "$avdb"
                      set -l di (contains -i -- "$avdb" $dbs)
                      if test -z "$di"
                        set -a dbs "$avdb"
                        set di (count $dbs)
                        for e in (jq -r '.branches[] | "\(.name)|\(.parent.name)|\(.parent.trunk // false)"' "$avdb" 2>/dev/null)
                          set -a edges "$di|$e"
                        end
                      end
                      set -l curb $branch
                      set -l depth 0
                      set -l hops 0
                      while test $hops -lt 12
                        set -l hit (string match -- "$di|$curb|*" $edges)[1]
                        test -z "$hit"; and break
                        set -l f (string split "|" -- $hit)
                        set depth (math $depth + 1)
                        test "$f[4]" = true; and break
                        set curb $f[3]
                        set hops (math $hops + 1)
                      end
                      if test $depth -gt 0
                        set label (string repeat -n $depth "· ")"↳ $branch"
                      end
                    end
                  end
                  printf "%-42s %s\n" "$name" "$label"
                end
              end | fzf --prompt="session> " --height=100% --layout=reverse --info=hidden
            )
            or return 1
            set -l target (string split -f1 " " -- (string trim $choice))
            command tmux switch-client -t "=$target"
          '';
        };

        shellInit = ''
          # Completion for wts: wts-native subcommands + common av passthroughs
          complete -f -c wts -n "__fish_use_subcommand" -a "fork adopt tree restack sync pr rm init land sessions help"
          complete -f -c wts -n "__fish_use_subcommand" -a "next prev switch log reparent branch commit squash reorder tidy diff fetch validate-db orphan"
          complete -f -c wts -n "__fish_seen_subcommand_from rm" -a '(
            set -l mr (git worktree list --porcelain 2>/dev/null | head -1 | string replace "worktree " "")
            set -l rn (basename $mr 2>/dev/null)
            set -l wd (dirname $mr 2>/dev/null)/$rn.worktrees
            test -d $wd 2>/dev/null; and command ls $wd 2>/dev/null
          )'
        '';
      };
    };
}
