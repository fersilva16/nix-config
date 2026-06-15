# worktree linear-stacked part — Linear-driven stacked fork: `wtl` issue
# selection + `wts fork`'s stacked child worktree. Picks (or AI-creates) a
# Linear issue, marks it In Progress, then forks a child worktree off the
# CURRENT branch using Linear's branch name and registers the stack edge with
# av so the PR targets the parent.
#
#   wtsl [<issue-id>] [<name>]   pick/accept an issue, fork a stack child
#   wtsl ai [<task>...]          AI-create an issue, then fork
{
  home =
    { lib, userCfg, ... }:
    lib.mkIf (userCfg.linear.enable && userCfg.av.enable) {
      programs.fish = {
        functions.wtsl = ''
          _git_clean_stale_lock

          if not set -q TMUX
            echo "wtsl: requires tmux"
            return 1
          end

          set -l main_root (git worktree list --porcelain 2>/dev/null | head -1 | string replace "worktree " "")
          if test -z "$main_root"
            echo "wtsl: not a git repo" >&2
            return 1
          end
          set -l repo_name (basename $main_root)
          set -l wt_base (dirname $main_root)

          # Capture the parent branch BEFORE creating the child worktree —
          # the stacked fork stacks the new branch on whatever is checked out
          # here. Refuse detached HEAD so the stack has a concrete parent.
          set -l parent (git rev-parse --abbrev-ref HEAD 2>/dev/null)
          if test -z "$parent" -o "$parent" = HEAD
            echo "wtsl: detached HEAD — checkout the parent branch first" >&2
            return 1
          end

          # Resolve the Linear issue. `wtsl ai ...` creates a fresh issue
          # (delegating flags like --todo/--attach to `lin ai`); otherwise
          # accept an issue ID arg or fall back to the gum picker.
          set -l issue_id
          set -l name
          if test "$argv[1]" = ai
            set -e argv[1]
            lin ai $argv
            or return 1
            set issue_id $_lin_ai_last_issue
            if test -z "$issue_id"
              echo "wtsl: no issue created" >&2
              return 1
            end
          else
            set issue_id $argv[1]
            if test -z "$issue_id"
              set -l selection (lin list | gum filter --header "Select issue")
              or return 1
              set issue_id (string match -r '[A-Z]+-\d+' -- $selection)
            end
            set name $argv[2]
          end

          # Worktree name (custom) — prompt when not supplied.
          if test -z "$name"
            set name (gum input --placeholder "worktree name" --header "Worktree")
            or return 1
            if test -z "$name"
              echo "wtsl: name required"
              return 1
            end
          end

          set -l session_parent (command tmux display-message -p '#{session_name}' | string split -m 1 '/')[1]
          set -l session_name "$session_parent/$name"

          # Session already exists: just switch.
          if command tmux has-session -t "=$session_name" 2>/dev/null
            command tmux switch-client -t "=$session_name"
            return 0
          end

          # Start the issue — marks In Progress and yields Linear's branch name.
          linear-cli i update $issue_id --state "In Progress" --assignee me
          or return 1
          set -l branch_name (lin branch $issue_id)

          set -l wt_path "$wt_base/$repo_name.worktrees/$name"

          # Create the stacked worktree+branch off the current (parent) branch,
          # named after the worktree but using Linear's branch (mirrors `wts fork`).
          wt $name $branch_name
          or return 1

          # Register the stack edge so PRs target the parent. Adopt needs at
          # least one commit; on an empty fork it's a no-op until the first
          # commit, so don't treat failure as fatal.
          if not av -C "$wt_path" adopt --parent "$parent" 2>/dev/null
            echo "wts: '$branch_name' forked from '$parent'. After your first commit, run 'wts adopt $parent' to register the stack." >&2
          end
        '';

        shellInit = ''
          # Completion for wtsl: ai subcommand (linear-driven stacked fork)
          complete -f -c wtsl -n "__fish_use_subcommand" -a "ai"
        '';
      };
    };
}
