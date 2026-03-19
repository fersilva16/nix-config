{
  username,
  pkgs,
  lib,
  ...
}:
{
  environment = {
    systemPackages = [ pkgs.fish ];
    shells = [ pkgs.fish ];
  };

  users.users.${username} = {
    shell = pkgs.fish;
  };

  programs.fish.enable = true;

  home-manager.users.${username} = {
    programs.fish = {
      enable = true;

      interactiveShellInit = ''
        ssh-add --apple-load-keychain 2> /dev/null

        set fish_cursor_default block
        set fish_cursor_insert line
        set -U fish_greeting

        fish_add_path -amP /usr/bin
        fish_add_path -amP /opt/homebrew/bin
        fish_add_path -amP /opt/local/bin
        fish_add_path -m /run/current-system/sw/bin
        fish_add_path -m /Users/fernando/.nix-profile/bin
      '';

      shellAliases = {
        g = "git";
        ga = "git add";
        gaa = "git add .";
        gb = "git branch";
        gc = "git commit";
        gp = "git push";
        ds = "nix develop . --command $SHELL";

        ls = "eza -lag";
        cat = "bat";
      };

      functions = {
        ghpc = "git push && gh pr create --fill $argv && gh pr view --web";
        ghpm = ''
          gh pr merge -s --admin $argv
          or return 1

          set main_root (git worktree list --porcelain | head -1 | string replace "worktree " "")
          set current_root (git rev-parse --show-toplevel)

          if test "$main_root" != "$current_root"; and set -q TMUX
            # In a worktree: pull main, then clean up
            git -C "$main_root" pull
            set wt_name (basename $current_root)
            wtrm --force $wt_name
          else
            # In the main repo: switch to default branch, pull, delete feature branch
            set feature_branch (git rev-parse --abbrev-ref HEAD)
            set default_branch (git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | string replace 'refs/remotes/origin/' "")
            if test -z "$default_branch"
              set default_branch main
            end
            git checkout "$default_branch"
            git pull
            git branch -D "$feature_branch" 2>/dev/null
          end
        '';
        ghpcm = "ghpc $argv && ghpm";

        pj = "cd $argv; ds";

        fish_command_not_found = "__fish_default_command_not_found_handler $argv";

        gco = ''
          set current_branch (git rev-parse --abbrev-ref HEAD)
          git checkout $argv; and if not string match -q -- '-*' $argv && test "$current_branch" != "$argv"
            git pull
          end
        '';

        envsource = ''
          for line in (cat $argv | grep -v '^#' | grep -v '^\s*$')
            set item (string trim $line | string replace -r '\s*=\s*' '=' | string split -m 1 '=')
            set -gx $item[1] $item[2]
            echo \"Exported key $item[1]\"
          end
        '';

        _git_clean_stale_lock = ''
          set -l git_dir (git rev-parse --git-dir 2>/dev/null)
          or return 0
          set -l lock "$git_dir/index.lock"
          if test -f "$lock"
            if not lsof "$lock" >/dev/null 2>&1
              rm -f "$lock"
              echo "Removed stale index.lock"
            end
          end
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

            set name (command ls "$wt_dir" | fzf --prompt="worktree> " --height=40%)
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

            if test -n "$branch"
              # Use existing branch, or create new branch from current
              if git show-ref --verify --quiet "refs/heads/$branch"
                git worktree add "$wt_path" "$branch"
              else if git show-ref --verify --quiet "refs/remotes/origin/$branch"
                git worktree add --track -b "$branch" "$wt_path" "origin/$branch"
              else
                git worktree add -b "$branch" "$wt_path" "$base_branch"
              end
            else
              # New branch (named after worktree) from current branch
              git worktree add -b "$name" "$wt_path" "$base_branch"
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

        _lin_me = ''
          linear-cli whoami --output json --no-pager --quiet 2>/dev/null | jq -r '.name // empty'
        '';

        _lin_issue_id = ''
          set -l branch (git rev-parse --abbrev-ref HEAD 2>/dev/null)
          or return 1
          set -l match (string match -r -i '([a-z]+-\d+)' -- $branch)
          if test (count $match) -ge 2
            string upper $match[2]
          else
            echo "lin: could not extract issue ID from branch: $branch" >&2
            return 1
          end
        '';

        lin = ''
          if test (count $argv) -eq 0
            set -l branch_issue (linear-cli context)
            if test (count $branch_issue) -eq 0
              return 1
            end
            linear-cli i get $branch_issue
            return
          end

          switch $argv[1]
            case view
              if test (count $argv) -ge 2
                linear-cli i get $argv[2..-1]
              else
                linear-cli context
              end

            case list
              set -l me (_lin_me)
              set -l fmt '{{identifier}}  [{{state.name}}]  {{priorityLabel}}  {{title}}'
              set -l filter_args --assignee "$me" --filter "state.name!=Done" --filter "state.name!=Canceled" --filter "state.name!=Duplicate" --format "$fmt" --no-pager --quiet
              if test (count $argv) -ge 2
                linear-cli i list $filter_args | grep -i -- "$argv[2..-1]"
              else
                linear-cli i list $filter_args
              end

            case all
              set -l fmt '{{identifier}}  [{{state.name}}]  {{priorityLabel}}  {{title}}'
              if test (count $argv) -ge 2
                linear-cli i list --assignee (_lin_me) --format "$fmt" --no-pager --quiet | grep -i -- "$argv[2..-1]"
              else
                linear-cli i list --assignee (_lin_me) --format "$fmt" --no-pager --quiet
              end

            case backlog
              set -l fmt '{{identifier}}  {{priorityLabel}}  {{title}}'
              if test (count $argv) -ge 2
                linear-cli i list --assignee (_lin_me) --filter "state.name=Backlog" --format "$fmt" --no-pager --quiet | grep -i -- "$argv[2..-1]"
              else
                linear-cli i list --assignee (_lin_me) --filter "state.name=Backlog" --format "$fmt" --no-pager --quiet
              end

            case todo
              set -l fmt '{{identifier}}  {{priorityLabel}}  {{title}}'
              if test (count $argv) -ge 2
                linear-cli i list --assignee (_lin_me) --filter "state.name=Todo" --format "$fmt" --no-pager --quiet | grep -i -- "$argv[2..-1]"
              else
                linear-cli i list --assignee (_lin_me) --filter "state.name=Todo" --format "$fmt" --no-pager --quiet
              end

            case progress inprogress
              set -l fmt '{{identifier}}  {{priorityLabel}}  {{title}}'
              if test (count $argv) -ge 2
                linear-cli i list --assignee (_lin_me) --filter "state.name=In Progress" --format "$fmt" --no-pager --quiet | grep -i -- "$argv[2..-1]"
              else
                linear-cli i list --assignee (_lin_me) --filter "state.name=In Progress" --format "$fmt" --no-pager --quiet
              end

            case done
              set -l fmt '{{identifier}}  {{priorityLabel}}  {{title}}'
              if test (count $argv) -ge 2
                linear-cli i list --assignee (_lin_me) --filter "state.name=Done" --format "$fmt" --no-pager --quiet | grep -i -- "$argv[2..-1]"
              else
                linear-cli i list --assignee (_lin_me) --filter "state.name=Done" --format "$fmt" --no-pager --quiet
              end

            case cancelled canceled
              set -l fmt '{{identifier}}  {{priorityLabel}}  {{title}}'
              if test (count $argv) -ge 2
                linear-cli i list --assignee (_lin_me) --filter "state.name=Canceled" --format "$fmt" --no-pager --quiet | grep -i -- "$argv[2..-1]"
              else
                linear-cli i list --assignee (_lin_me) --filter "state.name=Canceled" --format "$fmt" --no-pager --quiet
              end

            case duplicate
              set -l fmt '{{identifier}}  {{priorityLabel}}  {{title}}'
              if test (count $argv) -ge 2
                linear-cli i list --assignee (_lin_me) --filter "state.name=Duplicate" --format "$fmt" --no-pager --quiet | grep -i -- "$argv[2..-1]"
              else
                linear-cli i list --assignee (_lin_me) --filter "state.name=Duplicate" --format "$fmt" --no-pager --quiet
              end

            case create
              set -l title
              if test (count $argv) -ge 2
                set title (string join " " -- $argv[2..-1])
              else
                set title (gum input --placeholder "Issue title" --header "Title" --width 60)
                or return 1
                if test -z "$title"
                  echo "lin: title required" >&2
                  return 1
                end
              end

              set -l team (gum input --value "ENG" --header "Team" --width 20)
              or set team ENG

              set -l pri (gum choose --header "Priority" "0 - None" "4 - Low" "3 - Medium" "2 - High" "1 - Urgent")
              set -l priority (string match -r '^\d' -- $pri)

              set -l cmd linear-cli i create "$title" -t $team
              if test -n "$priority"; set -a cmd -p $priority; end

              if gum confirm "Assign to me?"
                set -a cmd -a me
              end

              set -l desc (gum write --placeholder "Description (Esc to skip)" --header "Description" --width 80)
              if test -n "$desc"; set -a cmd -d "$desc"; end

              set -l label_list (linear-cli l list --type issue --all --format "{{name}}" --no-pager --quiet 2>/dev/null)
              if test (count $label_list) -gt 0
                set -l labels (printf '%s\n' $label_list | gum filter --no-limit --header "Labels (Tab to select)")
                for lbl in $labels
                  test -n "$lbl"; and set -a cmd -l "$lbl"
                end
              end

              $cmd

            case start
              if test (count $argv) -ge 2
                linear-cli i start $argv[2] --checkout $argv[3..-1]
              else
                set -l sel (linear-cli i list --assignee (_lin_me) --no-pager 2>/dev/null | gum filter --header "Start issue")
                or return 1
                set -l id (string match -r '[A-Z]+-\d+' -- $sel)
                if test -z "$id"
                  echo "lin: could not extract issue ID" >&2
                  return 1
                end
                linear-cli i start $id --checkout
              end

            case done
              linear-cli done $argv[2..-1]

            case comment
              set -l id (_lin_issue_id)
              or return 1
              if test (count $argv) -ge 2
                linear-cli i comment $id -b (string join " " -- $argv[2..-1])
              else
                set -l body (gum write --placeholder "Comment body" --header "Comment" --width 80)
                or return 1
                if test -z "$body"
                  echo "lin: comment required" >&2
                  return 1
                end
                linear-cli i comment $id -b "$body"
              end

            case pr
              set -l id (_lin_issue_id)
              or return 1
              linear-cli g pr $id --web $argv[2..-1]

            case open
              set -l id
              if test (count $argv) -ge 2
                set id $argv[2]
              else
                set id (_lin_issue_id)
                or return 1
              end
              linear-cli i open $id

            case ai
              if test (count $argv) -lt 2
                echo "Usage: lin ai <task description>" >&2
                return 1
              end

              set -l task (string join " " -- $argv[2..-1])
              set -l available_labels (linear-cli l list --type issue --all --format "{{name}}" --no-pager --quiet 2>/dev/null | string join ", ")

              set -l prompt "Generate a Linear issue from this task. Return ONLY a raw JSON object (no markdown, no code blocks) with fields: title (concise string), description (markdown string with context and acceptance criteria), priority (integer: 1=urgent, 2=high, 3=medium, 4=low), labels (array of strings from available: $available_labels). Task: $task"

              gum style --faint "Generating issue with AI..."
              set -l result (opencode run -m "opencode/minimax-m2.5-free" "$prompt" 2>/dev/null)
              or begin; echo "lin: AI generation failed" >&2; return 1; end

              set -l ai_title (printf '%s\n' $result | jq -r '.title // empty')
              set -l ai_desc (printf '%s\n' $result | jq -r '.description // empty')
              set -l ai_priority (printf '%s\n' $result | jq -r '.priority // 3')
              set -l ai_labels (printf '%s\n' $result | jq -r '.labels[]? // empty')

              if test -z "$ai_title"
                echo "lin: could not parse AI response" >&2
                return 1
              end

              set -l pri_names "None" "Urgent" "High" "Medium" "Low"
              set -l pri_label $pri_names[(math $ai_priority + 1)]
              set -l labels_str (string join ", " -- $ai_labels)
              if test -z "$labels_str"; set labels_str "None"; end

              echo ""
              printf "Title: %s\nPriority: %s\nLabels: %s\n\n%s" "$ai_title" "$pri_label" "$labels_str" "$ai_desc" | \
                gum style --border rounded --padding "1 2" --border-foreground 212
              echo ""

              set -l action (gum choose --header "Action" "Create" "Edit" "Cancel")

              switch $action
                case Create
                  set -l cmd linear-cli i create "$ai_title" -t ENG -p $ai_priority -a me
                  if test -n "$ai_desc"; set -a cmd -d "$ai_desc"; end
                  for lbl in $ai_labels
                    set -a cmd -l "$lbl"
                  end
                  $cmd

                case Edit
                  set -l title (gum input --value "$ai_title" --header "Title" --width 60)
                  or return 1

                  set -l team (gum input --value "ENG" --header "Team" --width 20)
                  or set team ENG

                  set -l pri (gum choose --header "Priority" "0 - None" "4 - Low" "3 - Medium" "2 - High" "1 - Urgent")
                  set -l priority (string match -r '^\d' -- $pri)

                  set -l desc (gum write --header "Description (Esc when done)" --width 80 --value "$ai_desc")

                  set -l cmd linear-cli i create "$title" -t $team -a me
                  if test -n "$priority"; set -a cmd -p $priority; end
                  if test -n "$desc"; set -a cmd -d "$desc"; end

                  set -l label_list (linear-cli l list --type issue --all --format "{{name}}" --no-pager --quiet 2>/dev/null)
                  if test (count $label_list) -gt 0
                    set -l labels (printf '%s\n' $label_list | gum filter --no-limit --header "Labels (Tab to select)")
                    for lbl in $labels
                      test -n "$lbl"; and set -a cmd -l "$lbl"
                    end
                  end

                  $cmd

                case Cancel
                  return 0
              end

            case '*'
              linear-cli $argv
          end
        '';

        wtl = ''
          _git_clean_stale_lock

          set issue_id $argv[1]

          # No args: gum picker from your Linear issues
          if test -z "$issue_id"
            set -l selection (linear-cli i list --assignee (_lin_me) --no-pager 2>/dev/null | gum filter --header "Select issue")
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
          linear-cli i start $issue_id
          or return 1
          set branch_name (linear-cli g branch $issue_id)

          # Create worktree (custom name) with Linear's branch
          wt $name $branch_name
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

            set name (command ls "$wt_dir" | fzf --prompt="remove> " --height=40%)
            or return 1
          end

          set wt_path "$wt_base/$repo_name.worktrees/$name"

          if not test -d "$wt_path"
            echo "wtrm: no worktree found for '$name'"
            return 1
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

            set -l branch (git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null)

            # Pre-check for uncommitted changes (can't report errors after switching away)
            if test $force -eq 0
              if test -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)"
                echo "wtrm: worktree has uncommitted changes — use 'wtrm --force' to force"
                return 1
              end
            end

            # Build cleanup command (POSIX shell, runs server-side via tmux run-shell -b)
            set -l cleanup "tmux kill-session -t '=$current_session'"
            if test $force -eq 1
              set cleanup "$cleanup; git -C '$main_root' worktree remove --force '$wt_path'"
            else
              set cleanup "$cleanup; git -C '$main_root' worktree remove '$wt_path'"
            end
            if test -n "$branch" -a "$branch" != "HEAD"
              if test $force -eq 1
                set cleanup "$cleanup; git -C '$main_root' branch -D '$branch' 2>/dev/null"
              else
                set cleanup "$cleanup; git -C '$main_root' branch -d '$branch' 2>/dev/null"
              end
            end

            # Switch to parent, then schedule cleanup in background
            command tmux switch-client -t "=$parent_session"
            command tmux run-shell -b "$cleanup"
          else
            # Regular remove (from a different session)
            if set -q TMUX
              set -l target_session (command tmux list-sessions -F '#{session_name}' | grep "/$name\$" | head -1)
              if test -n "$target_session"
                command tmux kill-session -t "=$target_session"
              end
            end

            set -l branch (git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null)

            if test $force -eq 1
              git worktree remove --force "$wt_path"
            else
              git worktree remove "$wt_path"
            end
            or begin; echo "wtrm: worktree has changes — use 'wtrm --force $name' to force"; return 1; end

            if test -n "$branch" -a "$branch" != "HEAD"
              if test $force -eq 1
                git branch -D "$branch" 2>/dev/null
              else
                git branch -d "$branch" 2>/dev/null
              end
              and echo "Removed worktree '$name' and branch '$branch'"
              or echo "Removed worktree '$name' (branch '$branch' not fully merged — use 'wtrm --force $name' to force)"
            else
              echo "Removed worktree '$name'"
            end
          end
        '';
      };

      shellInit = ''
        # Completion for gco function
        complete -f -c gco -a '(git branch --all | string replace -r "^[\*\s]+" "" | string replace -r "^remotes/" "")'

        # Completion for wt: 1st arg = existing worktree names, 2nd arg = branches
        complete -f -c wt -n "test (count (commandline -opc)) -eq 1" -a '(
          set -l mr (git worktree list --porcelain 2>/dev/null | head -1 | string replace "worktree " "")
          set -l rn (basename $mr 2>/dev/null)
          set -l wd (dirname $mr 2>/dev/null)/$rn.worktrees
          test -d $wd 2>/dev/null; and command ls $wd 2>/dev/null
        )'
        complete -f -c wt -n "test (count (commandline -opc)) -eq 2" -a '(git branch -a --format="%(refname:short)" 2>/dev/null | string replace -r "^origin/" "" | sort -u | grep -v "^HEAD")'

        # Completion for lin: linear-cli issue subcommands
        complete -f -c lin -n "test (count (commandline -opc)) -eq 1" -a "view list all create ai start done cancelled duplicate comment pr open backlog todo progress"

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
