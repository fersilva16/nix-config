{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
mkUserModule {
  name = "linear";
  system.homebrew.casks = [ "linear-linear" ];
  home =
    { userCfg, ... }:
    {
      home.packages = with pkgs; [
        linear-cli
        gum
        jq
      ];

      # Fish shell integration: lin CLI wrapper and helper functions
      programs.fish = lib.mkIf userCfg.fish.enable {
        functions = {
          _lin_me = ''
            linear-cli whoami --output json --no-pager --quiet 2>/dev/null | jq -r '.name // empty'
          '';

          _lin_team_labels = ''
            set -l team_key $argv[1]
            linear-cli api query "{ team(id: \"$team_key\") { labels { nodes { id name } } } }" --output json --no-pager --quiet 2>/dev/null | jq -r '.data.team.labels.nodes[] | "\(.id)\t\(.name)"' 2>/dev/null
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

          _lin_show = ''
            linear-cli i get $argv --output json --no-pager --quiet 2>/dev/null | jq -r '
              "\(.identifier) \(.title)" as $h |
              ($h + "\n" + ("-" * ($h | length)) + "\n") +
              ((.description // "") | if . != "" then "\n" + . + "\n\n" else "\n" end) +
              "State:    " + (.state.name // "-") +
              "\nPriority: " + ((.priority // 0) as $p | ["None","Urgent","High","Medium","Low"] | .[$p]) +
              ([.labels.nodes[]?.name] | if length > 0 then "\nLabels:   " + join(", ") else "" end) +
              "\nURL:      " + (.url // "")
            '
          '';

          lin = ''
            if test (count $argv) -eq 0
              set -l branch_issue (linear-cli context)
              if test (count $branch_issue) -eq 0
                return 1
              end
              _lin_show $branch_issue
              return
            end

            switch $argv[1]
              case view
                if test (count $argv) -ge 2
                  _lin_show $argv[2..-1]
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

              case branch
                set -l id
                if test (count $argv) -ge 2
                  set id $argv[2]
                else
                  set id (_lin_issue_id)
                  or return 1
                end
                linear-cli g branch $id 2>/dev/null | string match -r 'Linear branch:\s*(.+)' | tail -1 | string trim

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

                set -l label_data (_lin_team_labels $team)
                if test (count $label_data) -gt 0
                  set -l label_names
                  for entry in $label_data
                    set -a label_names (string split \t -- $entry)[2]
                  end
                  set -l labels (printf '%s\n' $label_names | gum filter --no-limit --header "Labels (Tab to select)")
                  for lbl in $labels
                    if test -n "$lbl"
                      for entry in $label_data
                        set -l parts (string split \t -- $entry)
                        if test "$parts[2]" = "$lbl"
                          set -a cmd -l "$parts[1]"
                          break
                        end
                      end
                    end
                  end
                end

                $cmd

              case start
                if test (count $argv) -ge 2
                  linear-cli i update $argv[2] --state "In Progress" --assignee me
                  or return 1
                  linear-cli g checkout $argv[2] $argv[3..-1]
                else
                  set -l sel (linear-cli i list --assignee (_lin_me) --no-pager 2>/dev/null | gum filter --header "Start issue")
                  or return 1
                  set -l id (string match -r '[A-Z]+-\d+' -- $sel)
                  if test -z "$id"
                    echo "lin: could not extract issue ID" >&2
                    return 1
                  end
                  linear-cli i update $id --state "In Progress" --assignee me
                  or return 1
                  linear-cli g checkout $id
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

              case branch
                set -l id
                if test (count $argv) -ge 2
                  set id $argv[2]
                else
                  set id (_lin_issue_id)
                  or return 1
                end
                linear-cli g branch $id 2>/dev/null | string match -r 'Linear branch:\s*(.+)' | tail -1 | string trim

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
                set -l available_labels (_lin_team_labels ENG | cut -f2 | string join ", ")

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
                    set -l label_data (_lin_team_labels ENG)
                    for lbl in $ai_labels
                      for entry in $label_data
                        set -l parts (string split \t -- $entry)
                        if test "$parts[2]" = "$lbl"
                          set -a cmd -l "$parts[1]"
                          break
                        end
                      end
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

                    set -l label_data (_lin_team_labels $team)
                    if test (count $label_data) -gt 0
                      set -l label_names
                      for entry in $label_data
                        set -a label_names (string split \t -- $entry)[2]
                      end
                      set -l labels (printf '%s\n' $label_names | gum filter --no-limit --header "Labels (Tab to select)")
                      for lbl in $labels
                        if test -n "$lbl"
                          for entry in $label_data
                            set -l parts (string split \t -- $entry)
                            if test "$parts[2]" = "$lbl"
                              set -a cmd -l "$parts[1]"
                              break
                            end
                          end
                        end
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
        };

        shellInit = ''
          # Completion for lin: linear-cli issue subcommands
          complete -f -c lin -n "test (count (commandline -opc)) -eq 1" -a "view list all create ai start done cancelled duplicate comment pr open backlog todo progress"
        '';
      };
    };
}
