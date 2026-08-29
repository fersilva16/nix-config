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

      # Write markers, one empty file per task id: present in pending while the
      # write is in flight, moved to failed if it never lands.
      #
      # A directory rather than a queue file, and that is the whole reason there
      # is no lock anywhere below — every writer creates and removes exactly its
      # own entry, and mashing `x` is precisely the concurrent case. A shared
      # queue file would need one, and a lock is a thing that can be held by a
      # process that died.
      pending = ''"''${TMPDIR:-/tmp}/tmux-todoist-pending"'';
      failed = ''"''${TMPDIR:-/tmp}/tmux-todoist-failed"'';

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
          PENDING=${pending}
          PATH="${brewBin}:''${PATH}"

          # Claim the slot before the round trip: the widget decides staleness by
          # mtime and ticks every 5s, so without this it spawns a new refresh on
          # every tick for the whole duration of this one.
          touch "$CACHE"
          mkdir -p "$PENDING"

          tmp=$(mktemp) || exit 0
          pend=$(mktemp) || exit 0
          trap 'rm -f "$tmp" "$tmp.norm" "$pend"' EXIT

          # Everything, unfiltered: the cache is the shared store behind the
          # taskbar count and both picker tabs, and `today` is a jq predicate
          # applied at read time. Fetching `td today` here would make the
          # all-tasks tab impossible without a second round trip.
          #
          # ponytail: the CLI's default 300-task limit is the ceiling. --all
          # paginates, which is a slower call for a number that only has to be
          # roughly right; raise it if the count ever visibly plateaus at 300.
          td task list --json --limit 300 >"$tmp" 2>/dev/null || exit 0

          [ -s "$tmp" ] || exit 0
          jq -e '${wellFormed}' "$tmp" >/dev/null 2>&1 || exit 0

          # Read AFTER the fetch, deliberately: a task completed while this call
          # was in flight is still in the answer coming back, and putting that
          # row back on screen is the exact flicker the optimistic delete in
          # --complete exists to remove.
          ls -A "$PENDING" >"$pend" 2>/dev/null || true

          # Normalised to a bare array on the way in, so --complete can delete a
          # row with one map and no copy of the two-shape dance. unwrap stays
          # where it is — every reader still has to cope with a cache written
          # before this, and an array unwraps to itself.
          if jq --rawfile pend "$pend" '
                ($pend | split("\n")) as $done
                | ${unwrap}
                | map(select(.id | IN($done[]) | not))
              ' "$tmp" >"$tmp.norm" 2>/dev/null; then
            mv "$tmp.norm" "$CACHE"
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
          # nf-fa-refresh, same escape-not-paste rule as above.
          SYNC=$(printf '\uF021')

          # tmux's own 5s tick is the poll timer. Detached with stdout closed:
          # status-right captures this with $(), which would otherwise block
          # until the child exits.
          if ! find "$CACHE" -mmin -2 2>/dev/null | grep -q .; then
            ${tmux-todoist-refresh}/bin/tmux-todoist-refresh >/dev/null 2>&1 &
          fi

          # A marker two minutes old belongs to a writer that is never coming
          # back — a machine that slept mid-write, or a `td` that hung. The
          # trap above covers the one death we know about, and this covers the
          # rest: nothing else in the design ever clears a marker it did not
          # create, so without this the icon sticks on and refresh goes on
          # hiding a task that may never have been completed.
          #
          # -print before -delete so the same pass reports what it swept.
          # Silent, deliberately: a stuck marker means the outcome is unknown,
          # and the refresh below answers that honestly by putting the row back
          # if the server still has it. A red ! here would be claiming a failure
          # that may not have happened.
          if [ -n "$(find ${pending} -type f -mmin +2 -print -delete 2>/dev/null)" ]; then
            ${tmux-todoist-refresh}/bin/tmux-todoist-refresh >/dev/null 2>&1 &
          fi

          [ -f "$CACHE" ] || exit 0

          # Today only, always — the taskbar has no tab. A count that includes a
          # task due in three weeks is a number you stop reading.
          n=$(jq -r --arg today "$(date +%F)" \
                '${unwrap} | ${dueToday} | length' "$CACHE" 2>/dev/null) || exit 0
          case "''${n:-}" in "" | *[!0-9]*) exit 0 ;; esac

          # A suffix on the count, not a segment of its own: this is the state
          # OF that number, and a second segment is one more thing to parse at a
          # glance. Failure outranks in-flight because the row a failed write
          # removed is already back on the list, and unexplained that reads as a
          # bug rather than as a save that did not land.
          mark=""
          if [ -n "$(ls -A ${failed} 2>/dev/null)" ]; then
            mark=" #[fg=''${RED}]!"
          elif [ -n "$(ls -A ${pending} 2>/dev/null)" ]; then
            mark=" #[fg=''${FG},dim]''${SYNC}"
          fi

          # Silent at zero, like the disk and PR widgets: an empty list is the
          # reward state, and a segment that is always on screen is a segment
          # you stop seeing. An unfinished write is the one exception —
          # clearing your last task and having the save fail is exactly when
          # the segment must not vanish.
          [ "$n" -gt 0 ] || [ -n "$mark" ] || exit 0

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

          echo "#[fg=''${color},bg=''${BG},bold] ''${TD} ''${n}''${mark}''${RESET} "
        '';
      };

      # prefix+t. Menu mode by default so single letters are actions, `/`
      # switches to search and unbinds them for the duration, and every bind
      # that changes the rows also re-renders the header so the count can never
      # disagree with what is on screen.
      #
      # Two screens, and deliberately only two: the list, and one task. Both are
      # the same split, and the split never moves — the task list is always on
      # the left, the task itself is always on the right.
      #
      # What enter changes is which side is live. On the list the right pane is
      # a read-only render and the cursor is in the list; opening a task dims
      # the list and puts the cursor in the right pane, where the same fields
      # are now editable. Nothing is replaced and nothing slides across, so it
      # reads as attention moving rather than as a page turning — which is why
      # neither pane needs a key to summon it.
      #
      # What is gone is the separate edit form and the add wizard: three layouts
      # with three sets of keys for what is one object, where you had to
      # remember which page you were on before you could remember which key to
      # press.
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
          PENDING=${pending}
          FAILED=${failed}
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
            printf 'tab %s · enter edit · x done · a add · o web · r refresh · / search\n' "$other"
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

          # The same 11-column label gutter the detail rows use, so a field
          # being edited sits exactly where it sat while being read.
          form_pad() { printf '%s     %-10s%s' "$D" "$1" "$N"; }

          # Every editor opens on a cleared screen carrying the task's title.
          # Without it a gum prompt draws over whatever the pane happened to
          # contain, and one field out of context is not obviously about the
          # task you were just looking at.
          form_head() {
            printf '\033[2J\033[H'
            printf '\n  %s%s  %s%s\n' "$G" "$ICON" "''${1:-task}" "$N"
            printf '  %s%s%s\n\n' "$D" "──────────────────────────────────────────────" "$N"
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
            --complete)
              # Two round trips used to run inside this keypress — the write and
              # a full re-fetch — so ten `x` in a row cost twenty, and a batch
              # ran at the speed of the network. Now none do: the row is deleted
              # from the cache, which is the thing the list re-renders from, and
              # the write leaves detached behind it.
              [ -n "''${2:-}" ] || exit 0
              mkdir -p "$PENDING" "$FAILED"

              # Marked pending BEFORE the cache is touched. A refresh already in
              # flight reads this set and drops the id, so its answer — which
              # still contains the task — cannot put the row back.
              : >"$PENDING/$2"

              tmp=$(mktemp) || exit 0
              if jq --arg id "$2" '${unwrap} | map(select(.id != $id))' \
                   "$CACHE" >"$tmp" 2>/dev/null; then
                mv "$tmp" "$CACHE"
              else
                rm -f "$tmp"
              fi

              # Detached with both streams closed: execute-silent waits on the
              # child's pipes, so leaving stdout open would hand the round trip
              # straight back to the keypress it was just taken out of.
              (
                # This is the whole reason the write survives. tmux destroys the
                # popup pane the moment the picker exits, which SIGHUPs its
                # process group — and a backgrounded child is still in it. So
                # pressing x and then esc killed the writer mid-flight, leaving
                # the marker behind forever and the sync icon stuck on.
                #
                # Exactly what nohup does, inline because the body is a compound
                # statement and nohup takes a command. SIG_IGN survives exec, so
                # the `td` below ignores the signal too — which is the half that
                # actually matters.
                #
                # An empty double-quoted string, not the usual empty single
                # quotes: this is a nix indented string, where a pair of single
                # quotes is the terminator.
                trap "" HUP
                if td task complete "id:$2" --quiet >/dev/null 2>&1; then
                  rm -f "$PENDING/$2"
                else
                  # The server still has the task, so the refresh puts the row
                  # back — that IS the recovery, and the only reason the delete
                  # above is safe to do before the write. The marker exists so
                  # the return reads as "did not save" instead of a ghost.
                  touch "$FAILED/$2"
                  rm -f "$PENDING/$2"
                  ${tmux-todoist-refresh}/bin/tmux-todoist-refresh
                fi
              ) >/dev/null 2>&1 &
              exit 0
              ;;

            --show)
              # The reading half, and the whole reason there is a pane on the
              # right: the description. It is the one field a list row cannot
              # show and the detail row truncates to its first 60 characters,
              # which left a long note readable nowhere but the browser.
              #
              # Served out of the cache, not the network: this runs on every
              # cursor move, and a round trip per keystroke would make arrowing
              # through the list feel broken.
              #
              # Empty fields are skipped here, where --rows keeps them and shows
              # a dash. Opposite rules on purpose: this pane is for reading, and
              # a column of dashes is noise; that one is for editing, and a
              # field you cannot see is a field you cannot select to fill in.
              #
              # Same 11-column gutter as --rows, so stepping from the list into
              # the detail screen does not shift a single label sideways.
              [ -n "''${2:-}" ] || exit 0
              jq -r --arg id "$2" --arg today "$(date +%F)" '
                def dim:  "\u001b[2m" + . + "\u001b[0m";
                def red:  "\u001b[31m" + . + "\u001b[0m";
                def grn:  "\u001b[32m" + . + "\u001b[0m";
                def ylw:  "\u001b[33m" + . + "\u001b[0m";
                def bold: "\u001b[1m" + . + "\u001b[0m";
                def pad:  (. + "          ")[0:11] | dim;
                def row($k; $v):
                  if ($v // "") == "" then empty else "  " + ($k | pad) + $v end;

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
                        (if   (.priority // 1) == 4 then ("p1 · urgent" | red)
                         elif (.priority // 1) == 3 then ("p2 · medium" | ylw)
                         elif (.priority // 1) == 2 then "p3 · low"
                         else "" end)),
                      row("labels"; ((.labels // []) | join(", ")))
                    ]
                  + (if (.description // "") == "" then []
                     else [ "" ] + (.description | split("\n") | map("  " + .)) end)
                | .[]
              ' "$CACHE" 2>/dev/null
              exit 0
              ;;

            --rows)
              # The task, one field per line, in the same id-then-display TSV
              # shape the list uses — so the detail screen is the same fzf with
              # a different query, not a second kind of surface.
              #
              # Served out of the cache, like the list: pressing enter on a row
              # you can already see should not cost a round trip.
              #
              # Empty fields keep their row and show a dash. A field that
              # disappears when unset is a field you cannot select to fill in,
              # which is the entire reason the old form had a separate menu.
              #
              # ponytail: no project row. `td task list --json` returns
              # projectId and no name — the old form read .project_name, which
              # has never existed, so its prefill was always blank. With one
              # project the row is noise anyway, and `#project` on add still
              # works. Bring it back, via a projectId→name lookup, if this
              # account ever grows a second project.
              # The description is wrapped into rows of its own rather than
              # truncated onto the notes line. This pane is fzf's item list, and
              # a list item does not wrap however wide the pane is — so the only
              # way the full note is readable here is to emit it pre-broken.
              # Every one of those rows carries the `notes` key, so enter on any
              # line of a note edits the note, which is what pointing at it
              # means.
              [ -n "''${2:-}" ] || exit 0

              # fzf exports its own width to the children it spawns, which is
              # the only way this side knows how wide it is. Clamped at both
              # ends: unset on an older fzf would wrap at a negative width, and
              # a full-screen terminal would produce lines too long to scan.
              w=''${FZF_COLUMNS:-80}
              case "$w" in ''' | *[!0-9]*) w=80 ;; esac
              # Halved because this pane is one side of a 50% split, then docked
              # for the label gutter, fzf's pointer column and the row indent —
              # all of which sit left of the text and none of which fzf counts.
              w=$(( w / 2 - 20 ))
              [ "$w" -gt 72 ] && w=72
              [ "$w" -lt 24 ] && w=24

              jq -r --arg id "$2" --arg today "$(date +%F)" --argjson w "$w" '
                def dim:  "\u001b[2m" + . + "\u001b[0m";
                def red:  "\u001b[31m" + . + "\u001b[0m";
                def grn:  "\u001b[32m" + . + "\u001b[0m";
                def ylw:  "\u001b[33m" + . + "\u001b[0m";
                def bold: "\u001b[1m" + . + "\u001b[0m";
                def pad:  (. + "          ")[0:11] | dim;
                def row($k; $v):
                  [ $k, "  " + ($k | pad)
                       + (if ($v // "") == "" then ("—" | dim) else $v end) ]
                  | @tsv;
                # Greedy word wrap. Folds each word onto the current line while
                # it fits and starts a new one when it does not, so a long note
                # breaks on spaces instead of mid-word.
                def wrap($n):
                  [ splits("[ \t]+") ]
                  | map(select(length > 0))
                  | reduce .[] as $word ([];
                      if (length == 0) or ((.[-1] | length) + 1 + ($word | length) > $n)
                      then . + [$word]
                      else .[0:-1] + [ .[-1] + " " + $word ]
                      end);

                ${unwrap}
                | map(select(.id == $id))
                | (.[0] // empty)
                | [ row("task"; (.content | bold)),
                    row("due";
                      (if .due then
                         ((.due.string // .due.date) | tostring) as $s
                         | (if ((.due.date | tostring)[0:10]) < $today then ($s | red) else ($s | grn) end)
                       else "" end)),
                    row("priority";
                      (if   (.priority // 1) == 4 then ("p1 · urgent" | red)
                       elif (.priority // 1) == 3 then ("p2 · medium" | ylw)
                       elif (.priority // 1) == 2 then "p3 · low"
                       else "" end)),
                    row("labels"; ((.labels // []) | join(", ")))
                  ]
                + ( (.description // "")
                    | if . == "" then [ row("notes"; "") ]
                      else
                        [ splits("\n") ]
                        | map(wrap($w)) | add
                        | to_entries
                        | map([ "notes",
                                "  " + ((if .key == 0 then "notes" else "" end) | pad)
                                     + (.value | dim) ] | @tsv)
                      end )
                | .[]
              ' "$CACHE" 2>/dev/null
              exit 0
              ;;

            --listframe)
              # The left half of the detail screen: the list you came from, left
              # exactly where it was, with the task you opened marked. Pure
              # context — the cursor lives in the fields on the right — so it
              # carries no pointer of its own and every other row is dimmed.
              # That is the whole trick: opening a task moves focus across the
              # screen instead of replacing it.
              #
              # Sliced to begin a few rows above the current task, because a
              # marker below the fold marks nothing.
              [ -n "''${2:-}" ] || exit 0
              jq -r --arg id "$2" --arg view "$(view_get)" --arg today "$(date +%F)" '
                def dim: "\u001b[2m" + . + "\u001b[0m";
                def grn: "\u001b[32m" + . + "\u001b[0m";
                ${unwrap}
                | ${byView}
                | ${smartSort}
                | to_entries
                | (map(select(.value.id == $id)) | (.[0].key // 0)) as $at
                | (if $at > 3 then $at - 3 else 0 end) as $from
                | .[$from:]
                | map("  " + (if .value.id == $id
                              then (.value.content | grn)
                              else (.value.content | dim) end))
                | .[]
              ' "$CACHE" 2>/dev/null
              exit 0
              ;;

            --field)
              # One field, chosen by having the cursor on it. The old form asked
              # which field you meant from a menu at the bottom of a list you
              # were already pointing at — this is the same edit with the
              # question deleted.
              fld=''${2:-}
              id=''${3:-}
              [ -n "$fld" ] && [ -n "$id" ] || exit 0
              form_colors
              rec=$(form_field "$id" '((.due.isRecurring // false) | tostring)')
              form_head "$(form_field "$id" '.content')"
              ok=1
              msg=""

              case "$fld" in
                task)
                  cur=$(form_field "$id" '.content')
                  new=$(gum input --prompt "$(form_pad task)" --no-show-help \
                    --value "$cur" --width 0 --placeholder "what needs doing" \
                    --cursor.foreground 2 --placeholder.foreground 245) || exit 0
                  [ -n "$new" ] || exit 0
                  [ "$new" = "$cur" ] && exit 0
                  td task update "id:$id" --content "$new" >/dev/null 2>&1 || ok=0
                  ;;

                due)
                  # The four answers that cover almost every reschedule, as a
                  # list instead of a text field. Typing "tomorrow" to mean
                  # tomorrow is a sentence you compose to say a thing you could
                  # have pointed at, and it is the single most common edit here.
                  #
                  # Every preset resolves to YYYY-MM-DD rather than passing the
                  # word through, because that is the one form BOTH verbs above
                  # accept — so a preset moves a recurring task and keeps its
                  # repeat, with nothing in this branch knowing about repeats.
                  # The resolved date is shown next to the label so the list
                  # also answers "which day is that".
                  #
                  # GNU date, from coreutils in runtimeInputs. BSD date reads -d
                  # as a daylight-saving flag and would return today for all four.
                  pick=$(printf '%s\n' \
                    "today        $(date +%F):$(date +%F)" \
                    "tomorrow     $(date -d tomorrow +%F):$(date -d tomorrow +%F)" \
                    "this weekend $(date -d saturday +%F):$(date -d saturday +%F)" \
                    "next week    $(date -d 'next monday' +%F):$(date -d 'next monday' +%F)" \
                    "no date:__clear__" \
                    "custom…:__custom__" \
                    | gum choose --header "$(form_pad due)" --no-show-help \
                        --cursor "  ❯  " --cursor.foreground 2 --selected.foreground 2 \
                        --label-delimiter ":" --height 8) || exit 0

                  case "$pick" in
                    __custom__)
                      # The escape hatch for everything the four presets do not
                      # cover — "in 3 days", "every monday", a specific date.
                      # A recurring task is prefilled and prompted with its
                      # resolved date, not its rule: the field is going to a verb
                      # that only accepts YYYY-MM-DD, so offering "every monday"
                      # back would be handing over text guaranteed to be rejected.
                      if [ "$rec" = true ]; then
                        cur=$(form_field "$id" '.due.date')
                        ph="YYYY-MM-DD — keeps the repeat"
                      else
                        cur=$(form_field "$id" '.due.string // .due.date')
                        ph="friday · in 3 days · every monday"
                      fi
                      pick=$(gum input --prompt "$(form_pad due)" --no-show-help \
                        --value "$cur" --width 0 --placeholder "$ph" \
                        --cursor.foreground 2 --placeholder.foreground 245) || exit 0
                      [ -n "$pick" ] || exit 0
                      ;;
                    __clear__)
                      # Clearing the date of a recurring task is how you delete a
                      # repeat by accident: --no-due drops the rule with it, and
                      # nothing on screen would say so until the task failed to
                      # come back. Refused here; custom… can still do it.
                      if [ "$rec" = true ]; then
                        msg="that would drop the repeat — clear it from custom… if you mean to"
                        ok=2
                      fi
                      pick=""
                      ;;
                  esac

                  if [ "$ok" = 1 ]; then
                    apply_due "$id" "$pick" "$rec"
                    case $? in
                      0) ;;
                      2)
                        ok=2
                        msg="recurring task — use YYYY-MM-DD to keep the repeat"
                        ;;
                      *) ok=0 ;;
                    esac
                  fi
                  ;;

                priority)
                  # Plain labels, no label:value split. gum matches --selected
                  # against the LABEL, not the value behind the delimiter, so
                  # the split form silently left the cursor on "none" no matter
                  # what the task was — and a reflex enter then cleared the
                  # priority of the task you opened to look at. The flag is the
                  # label's first word instead, which needs no second list.
                  cur=$(form_field "$id" '
                    if   (.priority // 1) == 4 then "p1 · urgent"
                    elif (.priority // 1) == 3 then "p2 · medium"
                    elif (.priority // 1) == 2 then "p3 · low"
                    else "none" end')
                  new=$(gum choose --header "$(form_pad priority)" --no-show-help \
                    --cursor "  ❯  " --cursor.foreground 2 --selected.foreground 2 \
                    --selected "$cur" --height 5 \
                    "none" "p3 · low" "p2 · medium" "p1 · urgent") || exit 0
                  [ "$new" = "$cur" ] && exit 0
                  # p4 IS "no priority" in Todoist; there is no --no-priority.
                  if [ "$new" = none ]; then
                    td task update "id:$id" --priority p4 >/dev/null 2>&1 || ok=0
                  else
                    td task update "id:$id" --priority "''${new%% *}" >/dev/null 2>&1 || ok=0
                  fi
                  ;;

                labels)
                  # Multi-select over the account's real labels rather than a text
                  # field with `@` syntax: --labels replaces the whole set, so a
                  # typo here does not create a new label, it silently drops every
                  # label the task had. show-help stays on because multi-select
                  # toggles with `x`, not space, and nothing on screen says so.
                  cur=$(form_field "$id" '((.labels // []) | join(","))')
                  sel=$(td label list --json 2>/dev/null | jq -r '${unwrap} | .[].name' \
                    | gum choose --no-limit --header "$(form_pad labels)" \
                        --cursor "  ❯  " --cursor.foreground 2 --selected.foreground 2 \
                        --selected "$cur" --height 10) || exit 0
                  new=$(printf '%s' "$sel" | paste -sd, -)
                  [ "$new" = "$cur" ] && exit 0
                  # --labels replaces the set, so clearing every label needs its
                  # own flag rather than an empty list.
                  if [ -n "$new" ]; then
                    td task update "id:$id" --labels "$new" >/dev/null 2>&1 || ok=0
                  else
                    td task update "id:$id" --no-labels >/dev/null 2>&1 || ok=0
                  fi
                  ;;

                notes)
                  # show-help stays on here because enter submits and shift+enter
                  # makes a newline, which is the only binding you would not guess.
                  #
                  # An explicit width, never 0. At 0 the textarea stops soft
                  # wrapping and scrolls sideways to keep the cursor in view, so
                  # opening an existing note showed its last few words and no
                  # way to see the beginning — the text was all still there, but
                  # editing it meant scrolling blind.
                  cols=$(tput cols 2>/dev/null) || cols=80
                  case "$cols" in ''' | *[!0-9]*) cols=80 ;; esac
                  cols=$(( cols - 12 ))
                  [ "$cols" -gt 100 ] && cols=100
                  [ "$cols" -lt 30 ] && cols=30

                  cur=$(form_field "$id" '.description')
                  new=$(gum write --header "$(form_pad notes)" \
                    --value "$cur" --placeholder "context, links, the first step…" \
                    --prompt "     ┃ " --width "$cols" --height 8 \
                    --cursor.foreground 2 --placeholder.foreground 245) || exit 0
                  [ "$new" = "$cur" ] && exit 0
                  td task update "id:$id" --description "$new" >/dev/null 2>&1 || ok=0
                  ;;
              esac

              if [ "$ok" = 0 ]; then
                printf "\n  %s  could not save — try 'td auth status'%s\n" "$R" "$N"
                sleep 2
              elif [ "$ok" = 2 ]; then
                printf "\n  %s  %s%s\n" "$R" "$msg" "$N"
                sleep 2
              fi

              # ponytail: synchronous full refresh, so the row you just changed
              # is right when --rows re-reads the cache. That is a second round
              # trip on top of the write; patch the single row from `td task
              # view --json` instead if the pause after an edit ever grates.
              ${tmux-todoist-refresh}/bin/tmux-todoist-refresh
              exit 0
              ;;

            --detail)
              # One task, in the right-hand pane the task was already occupying.
              # The preview moves to the left and becomes the dimmed list, so
              # the two halves keep their meaning and only the live one changes
              # sides: the rows you were reading are now the rows you edit, and
              # the cursor is already on the field you moved it to.
              #
              # The same fzf as the list — same delimiter, same with-nth, same
              # reload-after-write — because a second screen that behaves
              # differently is a second screen to learn. reload keeps the cursor
              # where it was, so editing `due` leaves you on `due`.
              #
              # --no-input because a handful of rows need no search, which keeps
              # every letter free to be an action without the menu/search dance.
              [ -n "''${2:-}" ] || exit 0
              id=$2
              # refresh-preview as well as reload: the left half re-reads the
              # cache on its own, but the pane on the right is a separate child
              # process fzf will not re-run unless told, and a stale right half
              # beside a freshly edited left half is worse than no pane at all.
              d_edit='execute('"$self"' --field {1} '"$id"')+reload('"$self"' --rows '"$id"')+refresh-preview'
              $self --rows "$id" | fzf \
                --ansi --no-sort --layout=reverse --cycle \
                --delimiter='\t' --with-nth=2 \
                --disabled --no-input --info=hidden \
                --pointer='>' --gutter=' ' \
                --color='pointer:green,header:dim,preview-border:238' \
                --header 'enter edit · x done · o web · esc back' \
                --header-first \
                --preview "$self --listframe $id" \
                --preview-window 'left,50%,border-right' \
                --bind "enter:$d_edit" \
                --bind "x:execute-silent($self --complete $id)+abort" \
                --bind "o:execute-silent($self --open $id)" \
                --bind 'esc:abort' \
                --bind 'ctrl-c:abort' >/dev/null
              exit 0
              ;;

            --add)
              # One field, because Todoist's own quick-add syntax carries the
              # rest and the server does the parsing: `tomorrow`, `p1`,
              # `#project`, `@label` and `//notes` all come out as real fields.
              # Verified against the live API, not assumed — `@label` only binds
              # to a label that already exists, and stays in the text otherwise.
              #
              # This used to be five prompts in a row, which is four more
              # decisions than capture can afford. Anything the syntax does not
              # cover is a field on the detail screen, one keypress away, and
              # that is the same screen as everything else.
              form_colors
              form_head "new task"
              printf '  %s   today · tomorrow · friday · p1–p4 · #project · @label · //notes%s\n\n' "$D" "$N"
              text=$(gum input --prompt "$(form_pad task)" --no-show-help --width 0 \
                --placeholder "buy oat milk tomorrow p1 @errand //the oat one" \
                --cursor.foreground 2 --placeholder.foreground 245) || exit 0
              [ -n "$text" ] || exit 0

              # Loudly, not with `|| true`: a capture tool that silently drops
              # what you just typed is worse than one that refuses to take it.
              if ! td task quickadd "$text" >/dev/null 2>&1; then
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

          # The list you are about to read is the message: the task whose write
          # failed is back on it. Cleared here rather than on a timer, because
          # the widget's `!` should persist exactly until it has been seen, and
          # opening the picker is what seeing it means.
          rm -rf "$FAILED"

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
          # execute, not execute-silent: both take over the terminal for a gum
          # prompt or a nested fzf. execute-silent would run them blind, with the
          # cursor hidden and keystrokes going nowhere.
          b_add='execute('"$self"' --add)+'"$redraw"
          b_detail='execute('"$self"' --detail {1})+'"$redraw"
          b_refresh='execute-silent(${tmux-todoist-refresh}/bin/tmux-todoist-refresh)+'"$redraw"
          # Deliberately left bound in search mode, unlike x/a/r: tab is not a
          # character you can type into a query, so it costs nothing there and
          # widening the scope mid-search is exactly when you want it.
          b_toggle='execute-silent('"$self"' --toggle)+'"$redraw"
          # `o` joins x/a/r in here for the obvious reason: it is a letter, and a
          # search for "onboarding" that opens a browser on the first keystroke
          # is the exact failure this menu/search split exists to prevent.
          b_search='unbind(change)+unbind(x)+unbind(a)+unbind(r)+unbind(o)+unbind(/)+clear-query+change-prompt(/ )+enable-search'
          b_esc_back='clear-query+disable-search+change-prompt(> )+rebind(change)+rebind(x)+rebind(a)+rebind(r)+rebind(o)+rebind(/)+'"$redraw"
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
            --color='pointer:green,prompt:green,info:dim,header:dim,preview-border:238' \
            --header="$(header_line)" \
            --preview "$self --show {1}" \
            --preview-window 'right,50%,border-left,wrap' \
            --bind "enter:$b_detail" \
            --bind "o:$b_open" \
            --bind "x:$b_done" \
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
