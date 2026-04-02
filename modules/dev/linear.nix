{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  linear-cli-version = "0.3.15";

  linear-cli = pkgs.stdenvNoCC.mkDerivation {
    pname = "linear-cli";
    version = linear-cli-version;

    src =
      {
        aarch64-darwin = pkgs.fetchurl {
          url = "https://github.com/Finesssee/linear-cli/releases/download/v${linear-cli-version}/linear-cli-aarch64-apple-darwin.tar.gz";
          hash = "sha256-Uhr6/uNjkWi/aIkWO4G6gtrMrbQXMgg0AHW+bOQ/HRs=";
        };
      }
      .${pkgs.stdenvNoCC.hostPlatform.system}
        or (throw "linear-cli: unsupported system ${pkgs.stdenvNoCC.hostPlatform.system}");

    sourceRoot = ".";

    installPhase = ''
      runHook preInstall
      install -Dm755 linear-cli $out/bin/linear-cli
      runHook postInstall
    '';

    meta = {
      description = "A powerful CLI for Linear.app built with Rust";
      homepage = "https://github.com/Finesssee/linear-cli";
      license = lib.licenses.mit;
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
      platforms = [ "aarch64-darwin" ];
      mainProgram = "linear-cli";
    };
  };
in
mkUserModule {
  name = "linear";
  system.homebrew.casks = [ "linear-linear" ];
  home =
    { userCfg, ... }:
    {
      home.packages = [
        linear-cli
        pkgs.gum
        pkgs.jq
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

                            set -l cmd linear-cli i create "$title" -t $team -o json --quiet --no-pager
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

                            set -l create_result ($cmd 2>&1)
                            or begin; echo "lin: issue creation failed" >&2; printf '%s\n' $create_result; return 1; end

                            set -l issue_id (printf '%s\n' $create_result | jq -r '.identifier // empty' 2>/dev/null)
                            if test -n "$issue_id"
                              set -g _lin_ai_last_issue $issue_id
                              gum style --foreground 82 "  ✓ Created $issue_id"
                            else
                              printf '%s\n' $create_result
                            end

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

                            set -l prompt "You generate Linear issues from task descriptions.
            Return ONLY a raw JSON object (no markdown fences, no commentary).

            JSON schema: {\"title\": string, \"description\": string, \"priority\": int, \"labels\": string[], \"project_hint\": string|null}

            Rules:
            - title: concise, imperative (e.g. \"Fix input sizing for md/lg variants\")
            - description: 1-5 sentences, conversational, like an engineer writing a ticket. Use bullet points only when listing specific items. NO markdown headers, NO sections like Context/Acceptance Criteria, NO checkboxes. Preserve any URLs from the task exactly as-is (full Figma links, GitHub links, etc.) — do NOT paraphrase or omit them. Do NOT include instructions like \"assign to me\" in the description — those are commands, not content.
            - priority: 1=urgent 2=high 3=medium 4=low
            - labels: pick from available: $available_labels. Empty array if none fit.
            - project_hint: if the user mentions a project, extract their words as-is (e.g. \"react project\" or \"CDSS\"). null if no project mentioned. Do NOT invent a project name.

            Examples of good descriptions:
            - \"The input component has inconsistent sizing across md/lg variants. Need to standardize to 56px/64px respectively and normalize the overall styling.\"
            - \"Migrate the specialized scribeSessions mutations: \`solveSession\`, \`assignPatientAndSelector\`, and \`mapInjection\`.\"
            - \"Set up the Unimed data as discussed:\\n* Ensure institutions are visible in the dashboard\\n* Create user accounts for the doctors in the attached list\"

            Task: $task"

                            # Animated spinner while AI generates
                            set -l tmpfile (mktemp)
                            set -l errfile (mktemp)
                            gum spin --spinner dot --title "Generating issue with AI..." -- \
                              sh -c "opencode run -m 'opencode/minimax-m2.5-free' '$prompt' > '$tmpfile' 2> '$errfile'"

                            set -l result (cat $tmpfile)
                            set -l errs (cat $errfile)
                            rm -f $tmpfile $errfile

                            if test -z "$result"
                              echo "lin: AI generation failed" >&2
                              if test -n "$errs"
                                printf '%s\n' $errs | gum style --foreground 196 --faint
                              end
                              return 1
                            end

                            # Extract JSON — handle cases where model wraps in code fences
                            set -l json_str (printf '%s\n' $result | sed -n '/^{/,/^}/p')
                            if test -z "$json_str"
                              set json_str (printf '%s\n' $result | sed -n '/```/,/```/p' | grep -v '```')
                            end
                            if test -z "$json_str"
                              set json_str "$result"
                            end

                            set -l ai_title (printf '%s\n' $json_str | jq -r '.title // empty' 2>/dev/null)
                            set -l ai_desc (printf '%s\n' $json_str | jq -r '.description // empty' 2>/dev/null)
                            set -l ai_priority (printf '%s\n' $json_str | jq -r '.priority // 3' 2>/dev/null)
                            set -l ai_labels (printf '%s\n' $json_str | jq -r '.labels[]? // empty' 2>/dev/null)

                            # Resolve project: AI extracts hint, we fuzzy-match against real list
                            set -l ai_project ""
                            set -l project_hint (printf '%s\n' $json_str | jq -r '.project_hint // empty' 2>/dev/null)
                            if test -n "$project_hint"
                              set -l matches (linear-cli projects list --no-pager --quiet --format "{{name}}" --all 2>/dev/null | grep -i "$project_hint")
                              set -l match_count (count $matches)
                              if test $match_count -eq 1
                                set ai_project $matches[1]
                              else if test $match_count -gt 1
                                set ai_project (printf '%s\n' $matches | gum filter --header "Multiple projects match '$project_hint'")
                              else
                                gum style --faint "  ⚠ No project matching '$project_hint'"
                              end
                            end

                            if test -z "$ai_title"
                              echo "lin: could not parse AI response" >&2
                              printf '%s\n' $result | head -5 | gum style --faint
                              return 1
                            end

                            set -l pri_names "None" "Urgent" "High" "Medium" "Low"
                            set -l pri_label $pri_names[(math $ai_priority + 1)]
                            set -l labels_str (string join ", " -- $ai_labels)
                            if test -z "$labels_str"; set labels_str "none"; end

                            # Preview — render each field cleanly
                            echo ""
                            gum style --bold --foreground 212 "  $ai_title"
                            echo ""
                            echo "  Priority: $pri_label" | gum style --faint
                            echo "  Labels:   $labels_str" | gum style --faint
                            if test -n "$ai_project"
                              echo "  Project:  $ai_project" | gum style --faint
                            end
                            echo ""
                            if test -n "$ai_desc"
                              printf '%s' "$ai_desc" | fold -s -w 76 | gum style --border rounded --padding "0 2" --border-foreground 240 --margin "0 2"
                            end
                            echo ""

                            set -l action (gum choose --header "Action" "Create" "Edit" "Cancel")

                            switch $action
                              case Create
                                set -l cmd linear-cli i create "$ai_title" -t ENG -p $ai_priority -a me -o json --quiet --no-pager
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

                                set -l create_result ($cmd 2>&1)
                                or begin; echo "lin: issue creation failed" >&2; printf '%s\n' $create_result; return 1; end

                                set -l issue_id (printf '%s\n' $create_result | jq -r '.identifier // empty' 2>/dev/null)

                                # Attach to project if specified
                                if test -n "$ai_project" -a -n "$issue_id"
                                  linear-cli i update $issue_id --project "$ai_project" --quiet --no-pager 2>/dev/null
                                  or gum style --faint "  ⚠ Could not attach to project: $ai_project"
                                end

                                if test -n "$issue_id"
                                  set -g _lin_ai_last_issue $issue_id
                                  gum style --foreground 82 "  ✓ Created $issue_id"
                                  if test -n "$ai_project"
                                    gum style --faint "    Project: $ai_project"
                                  end
                                else
                                  printf '%s\n' $create_result
                                end

                              case Edit
                                set -l title (gum input --value "$ai_title" --header "Title" --width 60)
                                or return 1

                                set -l team (gum input --value "ENG" --header "Team" --width 20)
                                or set team ENG

                                set -l pri (gum choose --header "Priority" "0 - None" "4 - Low" "3 - Medium" "2 - High" "1 - Urgent")
                                set -l priority (string match -r '^\d' -- $pri)

                                set -l desc (gum write --header "Description (Esc when done)" --width 80 --value "$ai_desc")

                                # Project selection (pre-filled with AI suggestion)
                                set -l project "$ai_project"
                                set -l project_names (linear-cli projects list --no-pager --quiet --format "{{name}}" 2>/dev/null)
                                if test (count $project_names) -gt 0
                                  set -l proj_choice (begin; echo "(none)"; printf '%s\n' $project_names; end | gum filter --header "Project (Esc to skip)" --value "$project")
                                  if test -n "$proj_choice" -a "$proj_choice" != "(none)"
                                    set project "$proj_choice"
                                  else
                                    set project ""
                                  end
                                end

                                set -l cmd linear-cli i create "$title" -t $team -a me -o json --quiet --no-pager
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

                                set -l create_result ($cmd 2>&1)
                                or begin; echo "lin: issue creation failed" >&2; printf '%s\n' $create_result; return 1; end

                                set -l issue_id (printf '%s\n' $create_result | jq -r '.identifier // empty' 2>/dev/null)

                                if test -n "$project" -a -n "$issue_id"
                                  linear-cli i update $issue_id --project "$project" --quiet --no-pager 2>/dev/null
                                  or gum style --faint "  ⚠ Could not attach to project: $project"
                                end

                                if test -n "$issue_id"
                                  set -g _lin_ai_last_issue $issue_id
                                  gum style --foreground 82 "  ✓ Created $issue_id"
                                  if test -n "$project"
                                    gum style --faint "    Project: $project"
                                  end
                                else
                                  printf '%s\n' $create_result
                                end

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
