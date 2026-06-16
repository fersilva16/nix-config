# worktree linear-stacked part — Linear-driven stacked slice (git-stack-cli).
# Picks (or AI-creates) a Linear issue, marks it In Progress, then starts a NEW
# slice on the current stack as an empty commit titled with Linear's branch
# name. No worktree fork — the whole stack lives in one branch, so a slice is
# just a starter commit you build on, then carve into its own PR with `wts push`.
# Naming the commit after Linear's branch (which carries the issue id) makes the
# eventual PR auto-link back to the issue.
#
#   wtsl [<issue-id>]   pick/accept an issue, start a stacked slice
#   wtsl ai [<task>...]  AI-create an issue, then start a slice
{
  home =
    { lib, userCfg, ... }:
    lib.mkIf userCfg.linear.enable {
      programs.fish = {
        functions.wtsl = ''
          # Resolve the Linear issue. `wtsl ai ...` creates a fresh issue
          # (delegating flags like --todo/--attach to `lin ai`); otherwise
          # accept an issue-id arg or fall back to the gum picker.
          set -l issue_id
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
          end
          if test -z "$issue_id"
            echo "wtsl: no issue selected" >&2
            return 1
          end

          # Mark In Progress and resolve Linear's branch name (= the PR bookmark).
          linear-cli i update $issue_id --state "In Progress" --assignee me
          or return 1
          set -l branch_name (lin branch $issue_id)
          if test -z "$branch_name"
            echo "wtsl: could not resolve Linear branch name for $issue_id" >&2
            return 1
          end

          # Start a new slice: an empty starter commit titled with Linear's
          # branch name. Build your work on top, then `wts push` carves it into
          # its own PR (which auto-links to the issue via the branch name).
          git commit --allow-empty -m "$branch_name"
          or return 1
          echo "✓ started slice '$branch_name' on the stack — edit, commit, then 'wts push'"
        '';

        shellInit = ''
          # Completion for wtsl: ai subcommand (Linear-driven stacked slice)
          complete -f -c wtsl -n "__fish_use_subcommand" -a "ai"
        '';
      };
    };
}
