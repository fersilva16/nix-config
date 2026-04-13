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
        pkgs.pngpaste
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

          _lin_clipboard_image = ''
            # Extract clipboard image via pngpaste, print temp file path.
            set -l tmpfile (mktemp -t lin-clipboard-XXXXXX).png
            if pngpaste "$tmpfile" 2>/dev/null
              echo "$tmpfile"
            else
              rm -f "$tmpfile"
              return 1
            end
          '';

          _lin_upload_image = ''
            # Upload a file to Linear via fileUpload GraphQL mutation.
            # Usage: _lin_upload_image <filepath>
            # Prints the asset URL on success.
            set -l filepath $argv[1]
            if not test -f "$filepath"
              echo "lin: file not found: $filepath" >&2
              return 1
            end

            set -l content_type (file --mime-type -b "$filepath")
            set -l filename (basename "$filepath")
            set -l filesize (stat -f %z "$filepath")

            # Get signed upload URL from Linear
            set -l gql "mutation{fileUpload(contentType:\"$content_type\",filename:\"$filename\",size:$filesize){success uploadFile{uploadUrl assetUrl headers{key value}}}}"
            set -l response (linear-cli api mutate "$gql" --output json --quiet --no-pager 2>/dev/null)
            or begin; echo "lin: fileUpload mutation failed" >&2; return 1; end

            set -l success (printf '%s' "$response" | jq -r '.data.fileUpload.success' 2>/dev/null)
            if test "$success" != "true"
              echo "lin: fileUpload returned success=false" >&2
              return 1
            end

            set -l upload_url (printf '%s' "$response" | jq -r '.data.fileUpload.uploadFile.uploadUrl' 2>/dev/null)
            set -l asset_url (printf '%s' "$response" | jq -r '.data.fileUpload.uploadFile.assetUrl' 2>/dev/null)

            # Build curl headers from mutation response
            set -l curl_cmd curl -s -X PUT "$upload_url" \
              -H "Content-Type: $content_type" \
              -H "Cache-Control: public, max-age=31536000"

            set -l header_count (printf '%s' "$response" | jq '.data.fileUpload.uploadFile.headers | length' 2>/dev/null)
            for _hi in (seq 0 (math $header_count - 1))
              set -l hkey (printf '%s' "$response" | jq -r ".data.fileUpload.uploadFile.headers[$_hi].key" 2>/dev/null)
              set -l hval (printf '%s' "$response" | jq -r ".data.fileUpload.uploadFile.headers[$_hi].value" 2>/dev/null)
              set -a curl_cmd -H "$hkey: $hval"
            end
            set -a curl_cmd --data-binary "@$filepath" -o /dev/null -w '%{http_code}'

            # PUT file to signed URL
            set -l http_code ($curl_cmd)
            if not string match -q '2*' "$http_code"
              echo "lin: upload PUT failed (HTTP $http_code)" >&2
              return 1
            end

            echo "$asset_url"
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
                                        end | awk -F'[][]' '{
                                          s=$2
                                          if (s=="Backlog") p=1
                                          else if (s=="Todo") p=2
                                          else if (s=="In Review") p=3
                                          else if (s=="In Progress") p=4
                                          else p=9
                                          printf "%d\t%s\n", p, $0
                                        }' | sort -t\t -k1,1n | cut -f2-

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
                                        # Parse flags from argv before assembling task text
                                        set -l _todo_state false
                                        set -l _attach_files
                                        set -l _task_args

                                        set -l _i 2
                                        while test $_i -le (count $argv)
                                          switch "$argv[$_i]"
                                            case --todo
                                              set _todo_state true
                                            case --attach
                                              set -l _next (math $_i + 1)
                                              if test $_next -le (count $argv); and test -e "$argv[$_next]"
                                                set -a _attach_files "$argv[$_next]"
                                                set _i $_next
                                              else
                                                set -l _clip (_lin_clipboard_image)
                                                if test -n "$_clip"
                                                  set -a _attach_files "$_clip"
                                                  gum style --faint "  📎 Clipboard image captured"
                                                else
                                                  echo "lin: no image in clipboard" >&2
                                                  return 1
                                                end
                                              end
                                            case '*'
                                              set -a _task_args "$argv[$_i]"
                                          end
                                          set _i (math $_i + 1)
                                        end

                                        # Get task description
                                        set -l task
                                        if test (count $_task_args) -gt 0
                                          set task (string join " " -- $_task_args)
                                        else
                                          set task (gum write --placeholder "Describe the task..." --header "New issue" --width 80)
                                          or return 1
                                          if test -z "$task"
                                            echo "lin: task description required" >&2
                                            return 1
                                          end
                                        end

                                        set -l available_labels (_lin_team_labels ENG | cut -f2 | string join ", ")

                                        # Hint the AI about attached images
                                        set -l _task_for_ai "$task"
                                        if test (count $_attach_files) -gt 0
                                          set _task_for_ai "$task (note: "(count $_attach_files)" screenshot(s) will be attached to this issue)"
                                        end

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

                        Task: $_task_for_ai"

                                        # Animated spinner while AI generates
                                        set -l tmpfile (mktemp)
                                        set -l errfile (mktemp)
                                        set -l promptfile (mktemp)
                                        printf '%s' "$prompt" > $promptfile
                                        gum spin --spinner dot --title "Generating issue with AI..." -- \
                                          sh -c 'opencode run -m "opencode/minimax-m2.5-free" "$(cat "$1")" > "$2" 2> "$3"' _ "$promptfile" "$tmpfile" "$errfile"
                                        set -l ai_exit $status

                                        set -l result (cat $tmpfile)
                                        set -l errs (cat $errfile)
                                        rm -f $tmpfile $errfile $promptfile

                                        # Persist AI interaction for debugging
                                        set -l logdir ~/.local/share/lin
                                        mkdir -p $logdir
                                        set -l logfile $logdir/ai-last.log
                                        printf '=== lin ai @ %s ===\n--- prompt ---\n%s\n--- response (exit %d) ---\n%s\n--- stderr ---\n%s\n' \
                                          (date '+%Y-%m-%d %H:%M:%S') "$prompt" $ai_exit "$result" "$errs" > $logfile

                                        if test -z "$result"
                                          echo "lin: AI generation failed (exit $ai_exit)" >&2
                                          if test -n "$errs"
                                            printf '%s\n' $errs | gum style --foreground 196 --faint
                                          end
                                          gum style --faint "  see $logfile for details"
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

                                        while true

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
                                        if test (count $_attach_files) -gt 0
                                          echo "  📎 "(count $_attach_files)" image(s)" | gum style --faint
                                        end
                                        echo ""
                                        if test -n "$ai_desc"
                                          printf '%s' "$ai_desc" | fold -s -w 76 | gum style --border rounded --padding "0 2" --border-foreground 240 --margin "0 2"
                                        end
                                        echo ""

                                        set -l action (gum choose --header "Action" "Create" "Edit with AI" "Edit" "Attach image" "Cancel")

                                        switch $action
                                          case Create
                                            # Upload attached images and build markdown
                                            set -l _image_md ""
                                            if test (count $_attach_files) -gt 0
                                              for _img in $_attach_files
                                                set -l _bname (basename $_img)
                                                printf '  Uploading %s... ' "$_bname"
                                                set -l _url (_lin_upload_image "$_img" 2>/dev/null)
                                                if test -n "$_url"
                                                  set _image_md "$_image_md

            ![]($_url)"
                                                  gum style --foreground 82 "✓"
                                                else
                                                  gum style --foreground 196 "✗ failed"
                                                end
                                              end
                                            end

                                            set -l _full_desc "$ai_desc$_image_md"

                                            set -l cmd linear-cli i create "$ai_title" -t ENG -p $ai_priority -a me -o json --quiet --no-pager
                                            if test -n "$_full_desc"; set -a cmd -d "$_full_desc"; end
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

                                            if test "$_todo_state" = true -a -n "$issue_id"
                                              linear-cli i update $issue_id --state "Todo" --quiet --no-pager 2>/dev/null
                                            end

                                            if test -n "$issue_id"
                                              set -g _lin_ai_last_issue $issue_id
                                              gum style --foreground 82 "  ✓ Created $issue_id"
                                              if test -n "$ai_project"
                                                gum style --faint "    Project: $ai_project"
                                              end
                                              if test "$_todo_state" = true
                                                gum style --faint "    State: Todo"
                                              end
                                              if test (count $_attach_files) -gt 0
                                                gum style --faint "    📎 "(count $_attach_files)" image(s) attached"
                                              end
                                            else
                                              printf '%s\n' $create_result
                                            end
                                            # Clean up clipboard temp files
                                            for _img in $_attach_files
                                              if string match -q '*lin-clipboard-*' "$_img"
                                                rm -f "$_img"
                                              end
                                            end
                                            break

                                          case "Edit with AI"
                                            set -l instruction (gum write --placeholder "What to change..." --header "Refinement" --width 80)
                                            or continue
                                            if test -z "$instruction"; continue; end

                                            # Build current state as JSON for refinement
                                            set -l current_json (jq -n \
                                              --arg title "$ai_title" \
                                              --arg desc "$ai_desc" \
                                              --argjson priority $ai_priority \
                                              --arg ph "$project_hint" \
                                              '{title: $title, description: $desc, priority: $priority, project_hint: (if $ph != "" then $ph else null end), labels: []}')
                                            for lbl in $ai_labels
                                              set current_json (printf '%s' "$current_json" | jq --arg l "$lbl" '.labels += [$l]')
                                            end

                                            set -l refine_file (mktemp)
                                            set -l r_out (mktemp)
                                            set -l r_err (mktemp)
                                            printf 'You are refining a Linear issue. Current issue:\n%s\n\nRequested change: %s\n\nReturn ONLY the updated raw JSON object (no markdown fences, no commentary).\nSame schema: {"title": string, "description": string, "priority": int, "labels": string[], "project_hint": string|null}\nKeep fields unchanged unless the instruction implies a change.' "$current_json" "$instruction" > $refine_file

                                            gum spin --spinner dot --title "Refining with AI..." -- \
                                              sh -c 'opencode run -m "opencode/minimax-m2.5-free" "$(cat "$1")" > "$2" 2> "$3"' _ "$refine_file" "$r_out" "$r_err"
                                            set -l r_exit $status

                                            set -l r_result (cat $r_out)
                                            set -l r_errs (cat $r_err)
                                            set -l r_prompt (cat $refine_file)
                                            rm -f $refine_file $r_out $r_err

                                            # Persist refinement interaction for debugging
                                            set -l logdir ~/.local/share/lin
                                            mkdir -p $logdir
                                            set -l logfile $logdir/ai-last.log
                                            printf '\n=== lin ai refine @ %s ===\n--- prompt ---\n%s\n--- response (exit %d) ---\n%s\n--- stderr ---\n%s\n' \
                                              (date '+%Y-%m-%d %H:%M:%S') "$r_prompt" $r_exit "$r_result" "$r_errs" >> $logfile

                                            if test -z "$r_result"
                                              gum style --foreground 196 "  ✗ AI refinement failed (exit $r_exit)"
                                              if test -n "$r_errs"
                                                printf '%s\n' $r_errs | gum style --faint
                                              end
                                              gum style --faint "  see $logfile for details"
                                              continue
                                            end

                                            # Re-parse refined JSON
                                            set -l r_json (printf '%s\n' $r_result | sed -n '/^{/,/^}/p')
                                            if test -z "$r_json"
                                              set r_json (printf '%s\n' $r_result | sed -n '/```/,/```/p' | grep -v '```')
                                            end
                                            if test -z "$r_json"
                                              set r_json "$r_result"
                                            end

                                            set -l new_title (printf '%s\n' $r_json | jq -r '.title // empty' 2>/dev/null)
                                            if test -n "$new_title"
                                              set ai_title "$new_title"
                                              set ai_desc (printf '%s\n' $r_json | jq -r '.description // empty' 2>/dev/null)
                                              set ai_priority (printf '%s\n' $r_json | jq -r '.priority // 3' 2>/dev/null)
                                              set ai_labels (printf '%s\n' $r_json | jq -r '.labels[]? // empty' 2>/dev/null)
                                              set project_hint (printf '%s\n' $r_json | jq -r '.project_hint // empty' 2>/dev/null)
                                              # Re-resolve project
                                              set ai_project ""
                                              if test -n "$project_hint"
                                                set -l matches (linear-cli projects list --no-pager --quiet --format "{{name}}" --all 2>/dev/null | grep -i "$project_hint")
                                                if test (count $matches) -eq 1
                                                  set ai_project $matches[1]
                                                else if test (count $matches) -gt 1
                                                  set ai_project (printf '%s\n' $matches | gum filter --header "Multiple projects match '$project_hint'")
                                                end
                                              end
                                            else
                                              gum style --foreground 196 "  ✗ Could not parse refined response"
                                              printf '%s\n' $r_result | head -5 | gum style --faint
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

                                            # Upload attached images and append to description
                                            set -l _edit_image_md ""
                                            if test (count $_attach_files) -gt 0
                                              for _img in $_attach_files
                                                set -l _bname (basename $_img)
                                                printf '  Uploading %s... ' "$_bname"
                                                set -l _url (_lin_upload_image "$_img" 2>/dev/null)
                                                if test -n "$_url"
                                                  set _edit_image_md "$_edit_image_md

            ![]($_url)"
                                                  gum style --foreground 82 "✓"
                                                else
                                                  gum style --foreground 196 "✗ failed"
                                                end
                                              end
                                            end

                                            set -l _edit_full_desc "$desc$_edit_image_md"

                                            set -l cmd linear-cli i create "$title" -t $team -a me -o json --quiet --no-pager
                                            if test -n "$priority"; set -a cmd -p $priority; end
                                            if test -n "$_edit_full_desc"; set -a cmd -d "$_edit_full_desc"; end

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

                                            if test "$_todo_state" = true -a -n "$issue_id"
                                              linear-cli i update $issue_id --state "Todo" --quiet --no-pager 2>/dev/null
                                            end

                                            if test -n "$issue_id"
                                              set -g _lin_ai_last_issue $issue_id
                                              gum style --foreground 82 "  ✓ Created $issue_id"
                                              if test -n "$project"
                                                gum style --faint "    Project: $project"
                                              end
                                              if test "$_todo_state" = true
                                                gum style --faint "    State: Todo"
                                              end
                                              if test (count $_attach_files) -gt 0
                                                gum style --faint "    📎 "(count $_attach_files)" image(s) attached"
                                              end
                                            else
                                              printf '%s\n' $create_result
                                            end
                                            # Clean up clipboard temp files
                                            for _img in $_attach_files
                                              if string match -q '*lin-clipboard-*' "$_img"
                                                rm -f "$_img"
                                              end
                                            end
                                            break

                                          case "Attach image"
                                            set -l source (gum choose --header "Source" "Clipboard" "File path" "Back")
                                            switch $source
                                              case Clipboard
                                                set -l _clip (_lin_clipboard_image)
                                                if test -n "$_clip"
                                                  set -a _attach_files "$_clip"
                                                  gum style --foreground 82 "  📎 Clipboard image added"
                                                else
                                                  gum style --foreground 196 "  ✗ No image in clipboard"
                                                end
                                              case "File path"
                                                set -l _fp (gum input --placeholder "/path/to/image (drag & drop here)" --header "File path" --width 80)
                                                # Strip quotes that some terminals add around drag-dropped paths
                                                set _fp (string trim --chars "\"' " -- "$_fp")
                                                if test -f "$_fp"
                                                  set -a _attach_files "$_fp"
                                                  gum style --foreground 82 "  📎 Added: "(basename $_fp)
                                                else if test -n "$_fp"
                                                  gum style --foreground 196 "  ✗ Not found: $_fp"
                                                end
                                            end

                                          case Cancel
                                            # Clean up clipboard temp files
                                            for _img in $_attach_files
                                              if string match -q '*lin-clipboard-*' "$_img"
                                                rm -f "$_img"
                                              end
                                            end
                                            return 0
                                        end
                                        end

                                      case ai-log
                                        set -l logfile ~/.local/share/lin/ai-last.log
                                        if test -f $logfile
                                          cat $logfile
                                        else
                                          echo "lin: no AI log found (run 'lin ai' first)" >&2
                                          return 1
                                        end

                                      case '*'
                                        linear-cli $argv
                                    end
          '';
        };

        shellInit = ''
          # Completion for lin: linear-cli issue subcommands
          complete -f -c lin -n "test (count (commandline -opc)) -eq 1" -a "view list all create ai ai-log start done cancelled duplicate comment pr open backlog todo progress"
          complete -f -c lin -n "test (commandline -opc)[2] = ai" -l attach -d "Attach image (clipboard if no path, or file path)"
          complete -f -c lin -n "test (commandline -opc)[2] = ai" -l todo -d "Set issue state to Todo"
        '';
      };
    };
}
