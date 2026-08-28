{
  mkUserModule,
  forPlatform,
  pkgs,
  lib,
  ...
}:
# Todoist as the personal task store, reached two ways: `t` at the keyboard and
# an ambient count in the tmux bar, with prefix+T to triage.
#
# Todoist owns capture — Siri, share sheet, widgets, and natural-language dates
# on the phone are things a terminal cannot compete with. What it does not do is
# put the list where you already are all day, which is the half that decided
# every previous tool: notification nags habituate, ambient surfaces do not.
#
# `todoist-cli` is Doist's official CLI (npm `@doist/todoist-cli`, binary `td`),
# NOT the `todoist-cli-go` formula — that one is sachaos/todoist, a version
# behind Todoist's API v1 migration with known write breakage.
#
# Installed via homebrew rather than nix on purpose: it pulls `@napi-rs/keyring`
# (a native module) and runs a postinstall script, both of which fight the nix
# build sandbox for no benefit here.
#
# Auth lives in `td` itself — `td auth login`, stored in the OS keyring, or a
# TODOIST_API_TOKEN env var. Same division as linear-cli: the module installs
# the tool, the tool owns its credential. Nothing secret enters the nix store.
mkUserModule {
  name = "todoist";

  system = forPlatform {
    darwin.homebrew.brews = [ "todoist-cli" ];
  };

  extraOptions.warnAt = lib.mkOption {
    type = lib.types.int;
    default = 15;
    description = "Open-task count at which the tmux widget starts escalating.";
  };

  extraOptions.reviewAt = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = "06:00";
    example = "07:30";
    description = ''
      Local time of day, "HH:MM", for the daily start review. null disables it.
    '';
  };

  home =
    {
      cfg,
      userCfg,
      ...
    }:
    let
      cache = ''"''${TMPDIR:-/tmp}/tmux-todoist.json"'';

      # td is a homebrew binary, and writeShellApplication resets PATH to
      # runtimeInputs only — without this the widget silently finds no `td` and
      # the count never appears.
      brewBin = "/opt/homebrew/bin";

      # Both shapes are accepted because Todoist's API v1 returns
      # { results: [...], next_cursor } and the CLI may or may not unwrap it.
      #
      # Written as an explicit type test rather than `.results // .`: indexing an
      # ARRAY with a string key is a jq error, not a null, so the shorthand made
      # a bare-array response fail outright and render as an empty bar. The same
      # shorthand also fell through to `.` for an error object like
      # {"error":"unauthorized"}, whose `length` is its key count — reporting one
      # outstanding task when the real answer was "the token is dead".
      unwrap = ''(if type == "array" then . else (.results // []) end)'';

      # Publishing requires a recognisable envelope, not merely something that
      # unwraps to an array — otherwise an error object unwraps to [] and
      # overwrites a good cache with "you have nothing to do".
      wellFormed = ''type == "array" or (type == "object" and has("results"))'';

      # Due today or overdue — Todoist's own "Today" view, and the only list
      # worth having on screen all day. Overdue is in on purpose: hiding a
      # slipped task is how it stays slipped.
      #
      # Filtered here rather than fetched with `td today` so one cache can serve
      # both the taskbar count and both tabs of the picker. A second fetch for
      # the all-tasks tab would mean a second staleness window and a visible
      # pause on the keypress.
      #
      # Sliced to 10 chars because due.date is YYYY-MM-DD for a plain date but a
      # full datetime for a task with a time on it — comparing "2026-08-24T15:00"
      # against "2026-08-24" as strings is false, which would drop everything due
      # later today. $today is a jq --arg, supplied by the caller as `date +%F`.
      dueToday = "map(select(.due != null and ((.due.date | tostring)[0:10]) <= $today))";

      # Applied only in the today view; the all view is the identity. Kept as one
      # definition so the count in the taskbar and the rows in the pane can never
      # disagree about what "today" means.
      byView = ''(if $view == "today" then ${dueToday} else . end)'';

      # Todoist's own Smart sort — the documented order behind its Today and
      # Upcoming views: date and time (or the deadline, when there is no date),
      # then priority, then deadline, then manual order, then creation time.
      #
      # The last two keys are unreachable and deliberately dropped: day_order and
      # added_at are Sync-API fields that `td task list --json` does not return.
      # The three keys above settle every real list long before it gets there.
      #
      # Note this is "deadline only when there is no due date", not the earlier of
      # the two. A task due Monday with a Friday deadline is Monday's problem —
      # due is when you meant to work on it, deadline is only when it stops being
      # possible, and letting the deadline pull it forward would relitigate a
      # decision already made when the date was set.
      #
      # Sorts raw ISO strings rather than parsing dates, because ISO-8601 already
      # sorts lexicographically. The prefix rule then hands back the tie-break for
      # free: "2026-08-25" < "2026-08-25T15:00", so an all-day task sits above a
      # timed one on the same day, the way the calendar stacks them.
      #
      # Overdue needs no term of its own — the key ascends, so last week sorts
      # above today by construction. Oldest slip first is both Todoist's behaviour
      # and the only order that makes an ignored task louder rather than quieter.
      #
      # Undated rides the same key at "9999-12-31" instead of getting a separate
      # is-null term: it lands last, and still sorts by priority among its own.
      smartSort = ''sort_by([((.due.date // .deadline.date) // "9999-12-31"), (4 - (.priority // 1)), (.deadline.date // "9999-12-31")])'';

      tmux-todoist-refresh = pkgs.writeShellApplication {
        name = "tmux-todoist-refresh";
        bashOptions = [ ];
        runtimeInputs = with pkgs; [
          jq
          coreutils
        ];
        text = ''
          CACHE=${cache}
          PATH="${brewBin}:''${PATH}"

          # Claim the slot before the round trip: the widget decides staleness by
          # mtime and ticks every 5s, so without this it spawns a new refresh on
          # every tick for the whole duration of this one.
          touch "$CACHE"

          tmp=$(mktemp) || exit 0
          trap 'rm -f "$tmp"' EXIT

          # Everything, unfiltered: the cache is the shared store behind the
          # taskbar count and both picker tabs, and `today` is a jq predicate
          # applied at read time. Fetching `td today` here would make the
          # all-tasks tab impossible without a second round trip.
          #
          # ponytail: the CLI's default 300-task limit is the ceiling. --all
          # paginates, which is a slower call for a number that only has to be
          # roughly right; raise it if the count ever visibly plateaus at 300.
          td task list --json --limit 300 >"$tmp" 2>/dev/null || exit 0

          if [ -s "$tmp" ] && jq -e '${wellFormed}' "$tmp" >/dev/null 2>&1; then
            mv "$tmp" "$CACHE"
          fi
        '';
      };

      tmux-todoist-widget = pkgs.writeShellApplication {
        name = "tmux-todoist-widget";
        bashOptions = [ ];
        runtimeInputs = with pkgs; [
          jq
          findutils
          coreutils
        ];
        text = ''
          CACHE=${cache}

          # Flexoki light theme colors (same palette as the cpu/disk widgets)
          BG="#f2f0e5"
          FG="#100f0f"
          YELLOW="#d0a215"
          ORANGE="#da702c"
          RED="#d14d41"

          RESET="#[fg=''${FG},bg=''${BG},nobold,noitalics,nounderscore,nodim]"

          # nf-fa-tasks, written as an escape rather than pasted in — a bare
          # U+F0AE is invisible in every diff and survives only until some tool
          # in the chain normalises it away.
          TD=$(printf '\uF0AE')

          # tmux's own 5s tick is the poll timer. Detached with stdout closed:
          # status-right captures this with $(), which would otherwise block
          # until the child exits.
          if ! find "$CACHE" -mmin -2 2>/dev/null | grep -q .; then
            ${tmux-todoist-refresh}/bin/tmux-todoist-refresh >/dev/null 2>&1 &
          fi

          [ -f "$CACHE" ] || exit 0

          # Today only, always — the taskbar has no tab. A count that includes a
          # task due in three weeks is a number you stop reading.
          n=$(jq -r --arg today "$(date +%F)" \
                '${unwrap} | ${dueToday} | length' "$CACHE" 2>/dev/null) || exit 0
          case "''${n:-}" in "" | *[!0-9]*) exit 0 ;; esac

          # Silent at zero, like the disk and PR widgets: an empty list is the
          # reward state, and a segment that is always on screen is a segment
          # you stop seeing.
          [ "$n" -gt 0 ] || exit 0

          warn=${toString cfg.warnAt}
          if (( n < warn )); then
            color="''${FG}"
          elif (( n < warn * 2 )); then
            color="''${YELLOW}"
          elif (( n < warn * 3 )); then
            color="''${ORANGE}"
          else
            color="''${RED}"
          fi

          echo "#[fg=''${color},bg=''${BG},bold] ''${TD} ''${n}''${RESET} "
        '';
      };

      # prefix+T. Same shape as the PR picker: menu mode by default so single
      # letters are actions, `/` switches to search and unbinds them for the
      # duration, and every bind that changes the rows also re-renders the
      # header so the count can never disagree with what is on screen.
      tmux-todoist-pick = pkgs.writeShellApplication {
        name = "tmux-todoist-pick";
        bashOptions = [ ];
        runtimeInputs = with pkgs; [
          fzf
          jq
          gum
          coreutils
        ];
        text = ''
          CACHE=${cache}
          # Which tab is showing. fzf keeps no state of its own, so the tab has
          # to live somewhere both the toggle and the reload can read — the same
          # trick `t` uses for its index file.
          VIEW=''${TMPDIR:-/tmp}/tmux-todoist-view
          PATH="${brewBin}:''${PATH}"
          self="$0"

          view_get() {
            if [ -f "$VIEW" ]; then cat "$VIEW"; else echo today; fi
          }

          render() {
            # $view/$today go in as jq --args so the program itself stays in
            # single quotes — interpolating a shell variable into it would put
            # task text one quote away from being jq source.
            jq -r --arg view "$(view_get)" --arg today "$(date +%F)" '
              def dim: "\u001b[2m" + . + "\u001b[0m";
              def red: "\u001b[31m" + . + "\u001b[0m";
              def grn: "\u001b[32m" + . + "\u001b[0m";
              def ylw: "\u001b[33m" + . + "\u001b[0m";

              # p1 and p2 only. The sort has already clustered them, so the mark
              # is only there to say why — and a mark on most rows is not a mark.
              def pmark:
                if   (.priority // 1) == 4 then ("! " | red)
                elif (.priority // 1) == 3 then ("! " | ylw)
                else "" end;

              # Red once the date is behind us. Sorting floats overdue to the top,
              # but top-of-list and due-today read identically without a colour,
              # and not noticing is how the task slipped in the first place.
              #
              # Falls back to the deadline when there is no due date, mirroring
              # the sort key exactly — otherwise a dateless task sorts by a date
              # the row never shows, which reads as a bug.
              # Bound with `as` rather than piped straight into the if: a pipe
              # would make `.` the string, and .due.date inside the condition
              # would then be indexing a string, which is a hard jq error.
              def datemark:
                if .due then
                  ("  " + ((.due.string // .due.date) | tostring)) as $s
                  | (if ((.due.date | tostring)[0:10]) < $today then ($s | red) else ($s | grn) end)
                elif .deadline then ("  by " + .deadline.date | ylw)
                else "" end;

              # Only when a due date is already on the row; otherwise datemark is
              # already showing this exact deadline and would print it twice.
              def dlmark:
                if (.due and .deadline) then ("  by " + .deadline.date | dim) else "" end;

              ${unwrap}
              | ${byView}
              | ${smartSort}
              | .[]
              | [ .id, (pmark + .content + datemark + dlmark) ]
              | @tsv
            ' "$CACHE" 2>/dev/null
          }

          header_line() {
            local view other n
            view=$(view_get)
            if [ "$view" = today ]; then other=all; else other=today; fi
            n=$(jq -r --arg view "$view" --arg today "$(date +%F)" \
                  '${unwrap} | ${byView} | length' "$CACHE" 2>/dev/null) || n=0
            printf '%s %s\n' "''${n:-0}" "$view"
            # The tab hint names where you land, not where you are.
            printf 'tab %s · enter details · x done · s push · e edit · a add · o web · r refresh · / search\n' "$other"
          }

          # ── shared task form ──────────────────────────────────────────────
          # One form, two callers: --add starts empty and submits `td task add`,
          # --edit prefills from the cache and submits `td task update`. Sharing
          # it is the point — a second, separate edit form is exactly where the
          # two drift into different field sets and different key rules.
          #
          # Colours are ANSI indices rather than the widget's Flexoki hex: this
          # renders on the terminal's own background and should follow its
          # theme, exactly like the fzf list behind it. Set in a function rather
          # than at top level because --list runs on every reload keystroke and
          # has no use for any of it.
          form_colors() {
            D=$(printf '\033[2m')
            G=$(printf '\033[32m')
            R=$(printf '\033[31m')
            N=$(printf '\033[0m')
            ICON=$(printf '\uF0AE')
          }

          # Shared by the live prompt and the frozen row, which is the whole
          # trick below — it has to stay a single definition.
          form_pad() { printf '%s     %-10s%s' "$D" "$1" "$N"; }

          form_row() {
            [ -n "$2" ] || return 0
            printf '%s%s%s%s\n' "$(form_pad "$1")" "''${3:-}" "$2" "$N"
          }

          # Redrawn after every answer. Deliberately ends without a trailing
          # blank line: the next gum prompt has to land on the very line its own
          # frozen row will occupy, so a field does not jump when it is
          # committed and the form fills in place.
          form_draw() {
            printf '\033[2J\033[H'
            printf '\n  %s%s  %s%s\n' "$G" "$ICON" "''${form_title:-task}" "$N"
            printf '  %s%s%s\n\n' "$D" "──────────────────────────────────────────────" "$N"
            form_row task "$content"
            form_row due "$due" "$G"
            [ "$prio" = none ] || form_row priority "$prio" "$R"
            form_row project "$project"
            [ -z "$notes" ] || form_row notes "$(printf '%s' "$notes" | head -n1 | cut -c1-46)"
          }

          # Reads and writes the content/due/prio/project/notes globals, so a
          # caller prefills simply by setting them first. Returns 1 on esc.
          #
          # One rule for every field: enter accepts and an empty field is a
          # skip, esc abandons the whole form. Same esc as the list it opened
          # from — on edit that means nothing is written, not a partial save.
          # One function per field, so --add can run them in sequence and --edit
          # can run exactly one. Each reads its global as the prefill and writes
          # it back, and returns non-zero on esc.
          ask_task() {
            content=$(gum input --prompt "$(form_pad task)" --no-show-help \
              --value "$content" --placeholder "what needs doing" --width 0 \
              --cursor.foreground 2 --placeholder.foreground 245) || return 1
            [ -n "$content" ] || return 1
          }

          ask_due() {
            due=$(gum input --prompt "$(form_pad due)" --no-show-help \
              --value "$due" --width 0 --placeholder "''${due_ph:-tomorrow 9am · friday · every monday}" \
              --cursor.foreground 2 --placeholder.foreground 245) || return 1
          }

          # label:value, so the list reads as words and still submits `p1`.
          ask_prio() {
            prio=$(gum choose --header "$(form_pad priority)" --no-show-help \
              --cursor "  ❯  " --cursor.foreground 2 --selected.foreground 2 \
              --label-delimiter ":" --selected "''${prio:-none}" --height 5 \
              "none:none" "p3 · low:p3" "p2 · medium:p2" "p1 · urgent:p1") || return 1
          }

          # Skipped when there is nothing to choose between: a single-project
          # account should not be asked where the task goes.
          ask_project() {
            local pjson
            pjson=$(td project list --json 2>/dev/null)
            [ "$(printf '%s' "$pjson" | jq -r '${unwrap} | length' 2>/dev/null || echo 0)" -gt 1 ] || return 0
            project=$(printf '%s' "$pjson" | jq -r '${unwrap} | .[].name' \
              | gum choose --header "$(form_pad project)" --no-show-help \
                  --cursor "  ❯  " --cursor.foreground 2 --selected.foreground 2 \
                  --selected "$project" --height 8) || return 1
          }

          # Multi-select over the account's real labels rather than a text field
          # with `@` syntax: --labels replaces the whole set, so a typo here does
          # not create a new label, it silently drops every label the task had.
          # show-help stays on, for the same reason it does on notes: multi-select
          # toggles with `x`, not space, and nothing on screen would say so.
          # Space silently doing nothing is the failure this line prevents.
          ask_labels() {
            local sel
            sel=$(td label list --json 2>/dev/null | jq -r '${unwrap} | .[].name' \
              | gum choose --no-limit --header "$(form_pad labels)" \
                  --cursor "  ❯  " --cursor.foreground 2 --selected.foreground 2 \
                  --selected "$labels" --height 10) || return 1
            labels=$(printf '%s' "$sel" | paste -sd, -)
          }

          # show-help stays on here because enter submits and shift+enter makes a
          # newline, which is the only binding in this form you would not guess.
          ask_notes() {
            notes=$(gum write --header "$(form_pad notes)" \
              --value "$notes" --placeholder "context, links, the first step…" \
              --prompt "     ┃ " --width 0 --height 5 \
              --cursor.foreground 2 --placeholder.foreground 245) || return 1
          }

          # The add path: every field in order, because a new task starts empty
          # and there is nothing to pick between. Labels are deliberately absent
          # — `t buy milk tomorrow p1 @errand` is the fast path for a new task,
          # and quickadd already parses @label there. Edit has no such verb,
          # which is exactly why its labels field exists.
          form_run() {
            form_title=$1
            form_draw; ask_task || return 1
            form_draw; ask_due || return 1
            form_draw; ask_prio || return 1
            form_draw; ask_project || return 1
            form_draw; ask_notes || return 1
          }

          # One field per call, rather than one jq emitting TSV. The tab-split
          # version needs IFS set to a real tab, and every portable way to spell
          # that inside a nix indented string is a trap: command substitution
          # strips the tab, and the bash literal collides with nix quoting.
          # $2 is spliced in as jq source, so it stays single-quoted here — the
          # unwrap expression contains its own double quotes, and wrapping the
          # whole program in them nests quotes that neither shell nor jq reads
          # the way it looks. $id stays literal for jq's --arg.
          form_field() {
            jq -r --arg id "$1" \
              '${unwrap} | map(select(.id == $id)) | (.[0] | '"$2"') // ""' \
              ${cache} 2>/dev/null
          }

          # Moving a due date needs two different verbs, and picking the wrong
          # one silently destroys data. Measured against the real CLI:
          #
          #   update --due   takes natural language, and FLATTENS a repeat —
          #                  "every monday" becomes a single dated task
          #   reschedule     keeps the repeat, and takes YYYY-MM-DD only,
          #                  rejecting "friday" with INVALID_DATE
          #
          # So: plain tasks get the good prose input, recurring ones get the
          # verb that keeps them recurring. A recurring task with a phrase
          # reschedule cannot parse is refused (2) rather than quietly
          # flattened — losing a repeat is invisible until it fails to return.
          apply_due() {
            if [ -z "$2" ]; then
              td task update "id:$1" --no-due >/dev/null 2>&1
              return
            fi
            if [ "$3" = true ]; then
              case "$2" in
                [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*) ;;
                *) return 2 ;;
              esac
              td task reschedule "id:$1" "$2" >/dev/null 2>&1
              return
            fi
            td task update "id:$1" --due "$2" >/dev/null 2>&1
          }

          case "''${1:-}" in
            --list)
              render
              exit 0
              ;;
            --toggle)
              if [ "$(view_get)" = today ]; then echo all >"$VIEW"; else echo today >"$VIEW"; fi
              exit 0
              ;;
            --header)
              header_line
              exit 0
              ;;
            --open)
              [ -n "''${2:-}" ] || exit 0
              td task browse "id:$2" >/dev/null 2>&1 || true
              exit 0
              ;;
            --show)
              # Served out of the cache, not the network: this runs on every
              # cursor move while the preview is open, and a round trip per
              # keystroke would make arrowing through the list feel broken.
              #
              # The description is the whole point. It is the one field the row
              # cannot show and the one that answers "what did I mean by this",
              # which is otherwise a trip to the browser.
              [ -n "''${2:-}" ] || exit 0
              jq -r --arg id "$2" --arg today "$(date +%F)" '
                def dim:  "\u001b[2m" + . + "\u001b[0m";
                def red:  "\u001b[31m" + . + "\u001b[0m";
                def grn:  "\u001b[32m" + . + "\u001b[0m";
                def ylw:  "\u001b[33m" + . + "\u001b[0m";
                def bold: "\u001b[1m" + . + "\u001b[0m";

                # Same 10-column label gutter as the add form, so the two ways
                # of looking at one task line up instead of each having a style.
                def pad: (. + "          ")[0:10] | dim;
                def row($k; $v): if ($v // "") == "" then empty else "  " + ($k | pad) + $v end;

                ${unwrap}
                | map(select(.id == $id))
                | (.[0] // empty)
                | [ "", "  " + (.content | bold), "" ]
                  + [ row("due";
                        (if .due then
                           ((.due.string // .due.date) | tostring) as $s
                           | (if ((.due.date | tostring)[0:10]) < $today then ($s | red) else ($s | grn) end)
                         else "" end)),
                      row("deadline"; (if .deadline then (.deadline.date | ylw) else "" end)),
                      row("priority";
                        (if   (.priority // 1) == 4 then ("p1" | red)
                         elif (.priority // 1) == 3 then ("p2" | ylw)
                         elif (.priority // 1) == 2 then "p3"
                         else "" end)),
                      row("labels"; ((.labels // []) | join(", ")))
                    ]
                  + (if (.description // "") == "" then []
                     else [ "" ] + (.description | split("\n") | map("  " + .)) end)
                | .[]
              ' "$CACHE" 2>/dev/null
              exit 0
              ;;
            --complete)
              [ -n "''${2:-}" ] || exit 0
              td task complete "id:$2" --quiet >/dev/null 2>&1 || true
              ${tmux-todoist-refresh}/bin/tmux-todoist-refresh
              exit 0
              ;;
            --reschedule)
              # The review's most common verb, so it gets one field instead of
              # the whole form: deciding "not today" should cost one keystroke
              # and one phrase, or it does not happen at the moment it should.
              [ -n "''${2:-}" ] || exit 0
              form_colors

              rec=$(form_field "$2" '((.due.isRecurring // false) | tostring)')

              # A recurring task is prefilled and prompted with its resolved
              # date, not its rule: the field is going to a verb that only
              # accepts YYYY-MM-DD, so offering "every monday" back would be
              # handing over text guaranteed to be rejected.
              if [ "$rec" = true ]; then
                cur=$(form_field "$2" '.due.date')
                ph="YYYY-MM-DD — keeps the repeat"
              else
                cur=$(form_field "$2" '.due.string // .due.date')
                ph="tomorrow · friday · next week"
              fi

              new=$(gum input --prompt "$(form_pad push)" --no-show-help \
                --value "$cur" --width 0 --placeholder "$ph" \
                --cursor.foreground 2 --placeholder.foreground 245) || exit 0
              [ -n "$new" ] || exit 0

              apply_due "$2" "$new" "$rec"
              case $? in
                0) ;;
                2)
                  printf "\n  %s  recurring task — use YYYY-MM-DD to keep the repeat%s\n" "$R" "$N"
                  sleep 2
                  exit 0
                  ;;
                *)
                  printf "\n  %s  could not reschedule — try 'td auth status'%s\n" "$R" "$N"
                  sleep 2
                  exit 0
                  ;;
              esac
              ${tmux-todoist-refresh}/bin/tmux-todoist-refresh
              exit 0
              ;;
            --edit)
              [ -n "''${2:-}" ] || exit 0
              form_colors

              # Prefilled from the cache, not a fetch: the row you pressed `e`
              # on is already in it, and a round trip would stall the keypress.
              content=$(form_field "$2" '.content')
              [ -n "$content" ] || exit 0
              rec=$(form_field "$2" '((.due.isRecurring // false) | tostring)')
              recurring_refused=0
              # Recurring shows its resolved date for the same reason as the
              # push field: the value has to be something the verb will accept.
              if [ "$rec" = true ]; then
                due=$(form_field "$2" '.due.date')
                due_ph="YYYY-MM-DD — keeps the repeat"
              else
                due=$(form_field "$2" '.due.string // .due.date')
                due_ph="today · tomorrow · friday · next week"
              fi
              project=$(form_field "$2" '.project_name')
              notes=$(form_field "$2" '.description')
              labels=$(form_field "$2" '((.labels // []) | join(","))')
              prio=$(form_field "$2" '
                if   (.priority // 1) == 4 then "p1"
                elif (.priority // 1) == 3 then "p2"
                elif (.priority // 1) == 2 then "p3"
                else "none" end')

              content0=$content; due0=$due; prio0=$prio
              project0=$project; notes0=$notes; labels0=$labels

              # Pick the field, then edit only that one. Walking all five to fix
              # a date is the slow path this exists to remove — an edit is
              # almost always one field, and the other four are already right.
              form_title="edit task"
              form_draw
              case $(gum choose --header "$(form_pad edit)" --no-show-help \
                       --cursor "  ❯  " --cursor.foreground 2 \
                       --selected.foreground 2 --selected none --height 7 \
                       task due priority project labels notes) in
                task)     form_draw; ask_task     || exit 0 ;;
                due)      form_draw; ask_due      || exit 0 ;;
                priority) form_draw; ask_prio     || exit 0 ;;
                project)  form_draw; ask_project  || exit 0 ;;
                labels)   form_draw; ask_labels   || exit 0 ;;
                notes)    form_draw; ask_notes    || exit 0 ;;
                *) exit 0 ;;
              esac

              # Three commands because Todoist has three verbs, not because the
              # form does. Each fires only when its own field changed, so fixing
              # a title never touches the date or the project.
              args=()
              [ "$content" != "$content0" ] && args+=(--content "$content")
              [ "$notes" != "$notes0" ] && args+=(--description "$notes")
              if [ "$labels" != "$labels0" ]; then
                # --labels replaces the set, so clearing every label needs its
                # own flag rather than an empty list.
                if [ -n "$labels" ]; then args+=(--labels "$labels"); else args+=(--no-labels); fi
              fi
              if [ "$prio" != "$prio0" ]; then
                # p4 IS "no priority" in Todoist; there is no --no-priority.
                if [ "$prio" = none ]; then args+=(--priority p4); else args+=(--priority "$prio"); fi
              fi

              ok=1
              if [ ''${#args[@]} -gt 0 ]; then
                td task update "id:$2" "''${args[@]}" >/dev/null 2>&1 || ok=0
              fi

              # Same two-verb rule as --reschedule, via the same helper. A
              # refusal (2) is reported on its own line: it means the repeat was
              # kept and the date was not, which is not the same as a failure.
              if [ "$due" != "$due0" ]; then
                apply_due "$2" "$due" "$rec"
                case $? in
                  0) ;;
                  2) recurring_refused=1 ;;
                  *) ok=0 ;;
                esac
              fi

              if [ -n "$project" ] && [ "$project" != "$project0" ]; then
                td task move "id:$2" --project "$project" >/dev/null 2>&1 || ok=0
              fi

              if [ "$ok" = 0 ]; then
                form_draw
                printf "\n  %s  could not save — try 'td auth status'%s\n" "$R" "$N"
                sleep 2
              elif [ "$recurring_refused" = 1 ]; then
                form_draw
                printf "\n  %s  saved, but the date needs YYYY-MM-DD to keep the repeat%s\n" "$R" "$N"
                sleep 2
              fi
              ${tmux-todoist-refresh}/bin/tmux-todoist-refresh
              exit 0
              ;;
            --add)
              # A form rather than one line. quickadd's `p1 #Project` syntax can
              # carry due, priority and project, but nothing in it can carry a
              # description, and the syntax only helps if you remember it. Named
              # fields are the discoverable half; `t <text>` in a pane is still
              # the one-line fast path, so nothing that was quick got slower.
              form_colors
              content=""; due=""; prio="none"; project=""; notes=""
              form_run "new task" || exit 0

              args=("$content")
              [ -n "$due" ] && args+=(--due "$due")
              [ "$prio" != none ] && args+=(--priority "$prio")
              [ -n "$project" ] && args+=(--project "$project")
              [ -n "$notes" ] && args+=(--description "$notes")

              # Loudly, not with `|| true`: a capture tool that silently drops
              # what you just typed is worse than one that refuses to take it.
              if ! td task add "''${args[@]}" >/dev/null 2>&1; then
                form_draw
                printf "\n  %s  could not add — try 'td auth status'%s\n" "$R" "$N"
                sleep 2
                exit 0
              fi

              ${tmux-todoist-refresh}/bin/tmux-todoist-refresh
              exit 0
              ;;
          esac

          # Cold cache: fetch synchronously so the first open shows tasks rather
          # than an empty box. Later opens read whatever the widget refreshed.
          [ -f "$CACHE" ] || ${tmux-todoist-refresh}/bin/tmux-todoist-refresh

          # Every open starts on today. The view file outlives the popup, and a
          # pane that remembers you went looking at everything last night is a
          # pane that opens on everything tomorrow morning.
          echo today >"$VIEW"

          list=$(render)
          if [ -z "$list" ]; then
            list=$(printf '\t\033[2mnothing due today\033[0m')
          fi

          redraw='reload('"$self"' --list)+transform-header('"$self"' --header)'
          b_open='execute-silent('"$self"' --open {1})'
          b_done='execute-silent('"$self"' --complete {1})+'"$redraw"
          b_add='execute('"$self"' --add)+'"$redraw"
          # execute, not execute-silent: both open a gum prompt and need the
          # terminal handed over. execute-silent would run them blind, with the
          # cursor hidden and keystrokes going nowhere.
          b_edit='execute('"$self"' --edit {1})+'"$redraw"
          b_resched='execute('"$self"' --reschedule {1})+'"$redraw"
          b_refresh='execute-silent(${tmux-todoist-refresh}/bin/tmux-todoist-refresh)+'"$redraw"
          # Deliberately left bound in search mode, unlike x/a/r: tab is not a
          # character you can type into a query, so it costs nothing there and
          # widening the scope mid-search is exactly when you want it.
          b_toggle='execute-silent('"$self"' --toggle)+'"$redraw"
          # `o` joins x/a/r in here for the obvious reason: it is a letter, and a
          # search for "onboarding" that opens a browser on the first keystroke
          # is the exact failure this menu/search split exists to prevent.
          b_search='unbind(change)+unbind(x)+unbind(a)+unbind(r)+unbind(o)+unbind(s)+unbind(e)+unbind(/)+clear-query+change-prompt(/ )+enable-search'
          b_esc_back='clear-query+disable-search+change-prompt(> )+rebind(change)+rebind(x)+rebind(a)+rebind(r)+rebind(o)+rebind(s)+rebind(e)+rebind(/)+'"$redraw"
          # shellcheck disable=SC2016  # $FZF_PROMPT is fzf's, not bash's
          b_esc='transform~[ "$FZF_PROMPT" = "/ " ] && echo "'"$b_esc_back"'" || echo abort~'

          printf '%s\n' "$list" | fzf \
            --ansi --no-sort --layout=reverse --cycle \
            --delimiter='\t' --with-nth=2 \
            --disabled \
            --prompt='> ' \
            --info=inline-right \
            --pointer='>' \
            --gutter=' ' \
            --color='pointer:green,prompt:green,info:dim,header:dim' \
            --header="$(header_line)" \
            --preview "$self --show {1}" \
            --preview-window 'hidden,right,55%,border-left,wrap' \
            --bind "enter:toggle-preview" \
            --bind "o:$b_open" \
            --bind "x:$b_done" \
            --bind "s:$b_resched" \
            --bind "e:$b_edit" \
            --bind "a:$b_add" \
            --bind "r:$b_refresh" \
            --bind "tab:$b_toggle" \
            --bind "/:$b_search" \
            --bind 'change:clear-query' \
            --bind 'ctrl-c:abort' \
            --bind "esc:$b_esc"
        '';
      };

      # The gate's only exit. Split out as its own popup rather than a bind
      # inside the picker so prefix+T keeps its plain esc — the picker is a
      # tool the rest of the day and only the 06:00 run should be inescapable.
      #
      # --default=false is the point: the answer under a reflex Enter is "no",
      # so the gate survives exactly the autopilot it exists to interrupt.
      tmux-todoist-review-confirm = pkgs.writeShellApplication {
        name = "tmux-todoist-review-confirm";
        bashOptions = [ ];
        runtimeInputs = with pkgs; [
          gum
          coreutils
        ];
        text = ''
          # $1 sentinel to touch when confirmed, $2 due count for the prompt.
          gum confirm --default=false \
            --affirmative "done" --negative "back to list" \
            "reviewed all $2 due today?" && touch "$1"
        '';
      };

      reviewEnabled = cfg.reviewAt != null;

      # "06:00" → { Hour = 6; Minute = 0; }. toIntBase10 rather than toInt:
      # toInt parses as JSON, where a leading zero is invalid, so "06" is an
      # eval error — which the default value would hit on every build.
      reviewHM = lib.splitString ":" (if reviewEnabled then cfg.reviewAt else "0:0");
      reviewHour = lib.toIntBase10 (builtins.elemAt reviewHM 0);
      reviewMinute = lib.toIntBase10 (builtins.elemAt reviewHM 1);

      # The day's first look at the terminal opens the picker. Same popup as
      # prefix+T — the gate is the timing, not a second UI, so the keys you
      # already know are the keys that dismiss it.
      #
      # Fired by a launchd calendar agent rather than a shell or terminal hook.
      # Ghostty here stays open for weeks, so anything hung on starting a
      # session (the ghostty command, client-attached, fish init) fires either
      # never or on every pane. A wall-clock trigger is the only one that lines
      # up with "the start of the day" when the terminal itself never restarts.
      #
      # launchd is also the reason this needs no timezone handling of its own:
      # StartCalendarInterval is local wall-clock and follows the system zone,
      # so 06:00 stays 06:00 after a flight. Asleep at 6am is handled too —
      # launchd runs the job on wake, coalescing missed intervals into one.
      tmux-todoist-review = pkgs.writeShellApplication {
        name = "tmux-todoist-review";
        bashOptions = [ ];
        runtimeInputs = with pkgs; [
          jq
          tmux
          coreutils
        ];
        text = ''
          STATE="''${XDG_STATE_HOME:-$HOME/.local/state}/tmux-todoist-review"
          today=$(date +%F)

          [ "$(cat "$STATE" 2>/dev/null)" = "$today" ] && exit 0

          # The catch-up path runs from client-attached, which fires while the
          # client is still registering — both the check below and display-popup
          # would miss it. Costs a second once a day on the launchd path.
          sleep 1

          # No attached client means there is nowhere to draw. Bail BEFORE
          # claiming the day: at 06:00 with tmux not yet running, claiming here
          # would mark the review done and silently skip it. Leaving the marker
          # alone hands the day to the client-attached hook instead.
          [ -n "$(tmux list-clients -F '#{client_name}' 2>/dev/null)" ] || exit 0

          # Synchronous, unlike the widget's background refresh: this runs once
          # a day and the whole point is that the list is today's. A stale cache
          # here would gate you on yesterday's tasks.
          ${tmux-todoist-refresh}/bin/tmux-todoist-refresh

          n=$(jq -r --arg today "$today" \
                '${unwrap} | ${dueToday} | length' ${cache} 2>/dev/null)

          # Unreadable count means the fetch failed — a dead token or no network.
          # Leave the marker unwritten so the next trigger tries again, and never
          # hold the terminal hostage to Todoist being reachable.
          case "''${n:-}" in "" | *[!0-9]*) exit 0 ;; esac

          # Claimed before the popup, like the refresh claims its slot: the
          # launchd agent and the catch-up hook can land together, and only one
          # of them should gate. The cost is that abandoning the popup still
          # spends the day's prompt.
          #
          # ponytail: soft gate — esc closes it, and the count is only read
          # once. If dismissing it on autopilot becomes the habit, loop until
          # the due count actually drops rather than adding a nag.
          mkdir -p "$(dirname "$STATE")"
          echo "$today" >"$STATE"

          # Silent at zero, like the widget: an empty list is the reward state,
          # and a popup that says "nothing due" is training to dismiss popups.
          [ "$n" -gt 0 ] || exit 0

          # esc and ctrl-c close the picker but not the gate: every exit lands
          # on a confirm, and answering anything but "done" reopens the list.
          # That makes esc a no-op with a popup flash rather than a way out,
          # which is the whole ask — a single reflex key cannot end this.
          # Fixed path, not PID-suffixed: the day marker above is claimed before
          # we get here, so only one review can ever be in this loop.
          DONE="''${TMPDIR:-/tmp}/tmux-todoist-review-done"
          rm -f "$DONE"
          trap 'rm -f "$DONE"' EXIT

          # Bounded so a broken gum or tmux cannot spin popups forever — that
          # would be a real lockout, and the terminal you would fix it from is
          # the one behind the popup. 50 deliberate "back to list" answers is
          # far past reflex, so this only ever releases on breakage.
          i=0
          while [ "$i" -lt 50 ]; do
            i=$((i + 1))
            tmux display-popup -E -w 80% -h 60% '${tmux-todoist-pick}/bin/tmux-todoist-pick'
            tmux display-popup -E -w 52 -h 8 \
              "${tmux-todoist-review-confirm}/bin/tmux-todoist-review-confirm '$DONE' '$n'"
            [ -f "$DONE" ] && break
          done
        '';
      };
    in
    {
      home.packages = lib.mkIf userCfg.tmux.enable [
        tmux-todoist-refresh
        tmux-todoist-widget
        tmux-todoist-pick
        tmux-todoist-review
      ];

      programs.tmux.extraConfig = lib.mkIf userCfg.tmux.enable ''
        # Todoist triage popup. This deliberately overrides tmux's default
        # prefix+t clock-mode: the time is already in the menu bar, on the
        # phone, and on every other surface, so the key is better spent.
        # Matches the shell verb — `t` in a pane, prefix+t in tmux.
        bind-key t display-popup -E -w 80% -h 60% '${tmux-todoist-pick}/bin/tmux-todoist-pick'
        ${lib.optionalString reviewEnabled ''

          # Catch-up path only — the launchd agent above is what normally fires.
          # This covers the window the agent cannot reach: 06:00 arriving with
          # no tmux server (rebooted overnight, or the machine was off), where
          # the agent bails without claiming the day. First attach after that
          # runs the review instead.
          #
          # Appended rather than set: `set-hook -g` replaces the hook outright,
          # so a plain -g would silently drop anyone else's client-attached.
          # Backgrounded because this runs on the attach path — a synchronous
          # fetch would stall the terminal opening.
          #
          # The cost of -ga is that prefix+R stacks another copy for the life of
          # the server. Harmless by construction: every extra copy hits the
          # date marker on its first line and exits before doing any work.
          set-hook -ga client-attached 'run-shell -b "${tmux-todoist-review}/bin/tmux-todoist-review"'
        ''}
      '';

      # 46 keeps it beside the PR count (45) and left of cpu (50): attention
      # items first.
      xdg.configFile."tmux/widgets/46-todoist" = lib.mkIf userCfg.tmux.enable {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          exec ${tmux-todoist-widget}/bin/tmux-todoist-widget "$@"
        '';
      };

      programs.fish.functions = lib.mkIf userCfg.fish.enable {
        t = ''
          # Indices are resolved against the listing you last saw, not a fresh
          # fetch. Re-fetching would let a task added on the phone in between
          # shift the numbering, and `t done 2` would close the wrong thing.
          set -l idfile /tmp/t-ids-$USER

          set -l cmd ""
          if test (count $argv) -ge 1
            set cmd $argv[1]
          end

          # "done"/"rm" are only commands when followed by an index, so
          # `t done the dishes` still adds a task instead of misfiring.
          set -l is_cmd 0
          if contains -- "$cmd" done rm
            and test (count $argv) -eq 2
            and string match -qr '^\d+$' -- "$argv[2]"
            set is_cmd 1
          end

          # `t all` is the escape hatch out of the today-only default. Guarded by
          # argc like done/rm above, so `t all hands sync` still adds a task.
          set -l show_all 0
          if test "$cmd" = all
            and test (count $argv) -eq 1
            set show_all 1
          end

          if test (count $argv) -eq 0; or test $show_all -eq 1
            # `td today` means due-today-and-overdue. `t all` widens to every
            # open task, which is also the only way to see the ones carrying no
            # due date — those are invisible in the default view by definition.
            set -l fetch td today --json --limit 300
            set -l scope "due today"
            if test $show_all -eq 1
              set fetch td task list --json --limit 300
              set scope open
            end

            # Fetch and parse in two steps so a failed td is distinguishable
            # from an empty list. Piping straight into jq would report jq's
            # exit status, and an expired token would render as "nothing open".
            set -l json ($fetch 2>/dev/null)
            if test $status -ne 0
              echo "t: could not reach Todoist — try 'td auth status'" >&2
              return 1
            end

            # Same smartSort as the popup, from the same definition — two views
            # of one list that disagree about order is worse than either order.
            # The trailing field is the overdue flag: computed here because this
            # is where $today is, and fish only has the human due string.
            set -l rows (printf '%s\n' $json | jq -r --arg today (date +%F) '${unwrap} | ${smartSort} | .[] | [.id, .content, ((.due.string // .deadline.date) // ""), (.priority // 1), (if (.due and ((.due.date | tostring)[0:10]) < $today) then "od" else "" end)] | @tsv')

            if test (count $rows) -eq 0
              echo "  "(set_color green)"✓"(set_color normal)" nothing $scope"
              rm -f $idfile
              return 0
            end

            printf '%s\n' $rows | cut -f1 > $idfile

            set -l i 0
            for row in $rows
              set i (math $i + 1)
              set -l f (string split \t -- $row)
              # Todoist priority is inverted: 4 is p1, the urgent one.
              set -l mark "  "
              if test "$f[4]" = 4
                set mark (set_color red)" !"(set_color normal)
              else if test "$f[4]" = 3
                set mark (set_color yellow)" !"(set_color normal)
              end
              set -l due ""
              if test -n "$f[3]"
                # Red for a date already behind us, matching the popup. Sorting
                # puts these first; without the colour first just looks arbitrary.
                set -l c green
                if test "$f[5]" = od
                  set c red
                end
                set due "  "(set_color $c)"$f[3]"(set_color normal)
              end
              printf '%s %s%2d%s  %s%s\n' "$mark" (set_color brblack) $i (set_color normal) "$f[2]" "$due"
            end

            set -l n (count $rows)
            if test $n -ge ${toString cfg.warnAt}
              echo "  "(set_color yellow)"$n $scope — drop what you are not going to do: t rm <n>"(set_color normal)
            end

          else if test $is_cmd -eq 1
            if not test -f $idfile
              echo "t: run 't' first so indices refer to something" >&2
              return 1
            end
            set -l ids (cat $idfile)
            set -l n $argv[2]
            if test $n -lt 1 -o $n -gt (count $ids)
              echo "t: no open item $n" >&2
              return 1
            end
            set -l id $ids[$n]
            if test "$cmd" = done
              td task complete "id:$id" --quiet >/dev/null 2>&1
              and echo "  "(set_color green)"✓"(set_color normal)" done"
              or begin
                echo "t: could not complete item $n" >&2
                return 1
              end
            else
              # --yes, not --quiet: delete is the one verb that asks for
              # confirmation, and without it td prints "Use --yes to confirm"
              # and exits 0 — so this branch reported "dropped" and deleted
              # nothing. --quiet is not a flag delete has ever had.
              td task delete "id:$id" --yes >/dev/null 2>&1
              and echo "  "(set_color brblack)"dropped"(set_color normal)
              or begin
                echo "t: could not delete item $n" >&2
                return 1
              end
            end
            # The cached indices no longer match the server, so force a re-list
            # rather than let the next `t done` act on a stale row.
            rm -f $idfile

          else if contains -- "$cmd" today upcoming inbox
            and test (count $argv) -eq 1
            td $cmd

          else
            # quickadd, so Todoist's natural-language parsing applies:
            # `t buy oat milk tomorrow p1` sets the date and priority.
            td task quickadd (string join " " -- $argv) >/dev/null 2>&1
            and echo "  "(set_color green)"✓"(set_color normal)" added"
            or begin
              echo "t: could not add task — try 'td auth status'" >&2
              return 1
            end
          end
        '';
      };
    }
    # The daily trigger. Structurally absent on linux rather than mkIf'd:
    # launchd options do not exist there at all. The systemd timer port is
    # deferred until this repo actually has a linux host, matching ledger.
    // forPlatform {
      darwin.launchd.agents.tmux-todoist-review = lib.mkIf (userCfg.tmux.enable && reviewEnabled) {
        enable = true;
        config = {
          ProgramArguments = [ "${tmux-todoist-review}/bin/tmux-todoist-review" ];
          # Local wall-clock, and launchd re-derives it from the system
          # timezone — 06:00 stays 06:00 after a flight, with no TZ
          # handling in the script.
          StartCalendarInterval = [
            {
              Hour = reviewHour;
              Minute = reviewMinute;
            }
          ];
          # A login at 3pm should not fire the morning review; the
          # calendar interval (plus launchd's run-on-wake for a missed
          # one) is the only thing that should start this.
          RunAtLoad = false;
          ProcessType = "Interactive";
        };
      };
    };
}
