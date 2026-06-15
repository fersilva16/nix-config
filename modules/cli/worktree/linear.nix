# worktree linear part — Linear-driven worktrees. `wtl` picks/accepts a Linear
# issue, marks it In Progress, and spins up a worktree on its branch; `wtlc`
# creates (or AI-creates) an issue first, then does the same.
{
  home =
    { lib, userCfg, ... }:
    lib.mkIf userCfg.linear.enable {
      programs.fish.functions = {
        wtl = ''
          _git_clean_stale_lock

          set issue_id $argv[1]

          # No args: gum picker from your Linear issues
          if test -z "$issue_id"
            set -l selection (lin list | gum filter --header "Select issue")
            or return 1
            set issue_id (string match -r '[A-Z]+-\d+' -- $selection)
          end

          # Get worktree name (2nd arg or prompt)
          set name $argv[2]
          if test -z "$name"
            set name (gum input --placeholder "worktree name" --header "Worktree")
            or return 1
            if test -z "$name"
              echo "wtl: name required"
              return 1
            end
          end

          if not set -q TMUX
            echo "wtl: requires tmux"
            return 1
          end

          set parent_session (command tmux display-message -p '#{session_name}' | string split -m 1 '/')[1]
          set session_name "$parent_session/$name"

          # Session already exists: just switch
          if command tmux has-session -t "=$session_name" 2>/dev/null
            command tmux switch-client -t "=$session_name"
            return 0
          end

          # Start issue — marks In Progress and gets branch name
          linear-cli i update $issue_id --state "In Progress" --assignee me
          or return 1
          set branch_name (lin branch $issue_id)

          # Create worktree (custom name) with Linear's branch
          wt $name $branch_name
        '';

        wtlc = ''
          _git_clean_stale_lock

          if not set -q TMUX
            echo "wtlc: requires tmux"
            return 1
          end

          set -l mode create
          if test "$argv[1]" = ai
            set mode ai
            set -e argv[1]
          end

          # Delegate issue creation to lin (create or ai)
          if test "$mode" = ai
            lin ai $argv
          else
            lin create $argv
          end
          or return 1

          set -l issue_id $_lin_ai_last_issue
          if test -z "$issue_id"
            echo "wtlc: no issue created" >&2
            return 1
          end

          # Prompt for worktree name
          set -l name (gum input --placeholder "worktree name" --header "Worktree")
          or return 1
          if test -z "$name"
            echo "wtlc: name required"
            return 1
          end

          set parent_session (command tmux display-message -p '#{session_name}' | string split -m 1 '/')[1]
          set session_name "$parent_session/$name"

          # Session already exists: just switch
          if command tmux has-session -t "=$session_name" 2>/dev/null
            command tmux switch-client -t "=$session_name"
            return 0
          end

          # Start issue — marks In Progress and gets branch name
          linear-cli i update $issue_id --state "In Progress" --assignee me
          or return 1
          set branch_name (lin branch $issue_id)

          # Create worktree with Linear's branch
          wt $name $branch_name
        '';
      };
    };
}
