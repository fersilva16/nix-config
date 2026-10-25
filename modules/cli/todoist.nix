{
  mkUserModule,
  forPlatform,
  inputs,
  lib,
  ...
}:
# Todoist as the personal task store: `t` at the keyboard and an always-visible
# Hammerspoon panel. The tmux widget, the triage popup and the daily review ship
# in Limi (limi-suite reads warnAt and reviewAt from here).
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

  extraOptions = {
    warnAt = lib.mkOption {
      type = lib.types.int;
      default = 15;
      description = "Open-task count at which Limi's Todoist widget starts escalating.";
    };

    reviewAt = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "06:00";
      example = "07:30";
      description = ''
        Local time of day, "HH:MM", for Limi's daily start review. null disables it.
      '';
    };

    # The ambient half. The tmux widget puts a count where you already are; this
    # puts the rows there, on a monitor, above everything, on every Space — the
    # surface that needs neither a keypress nor a visible terminal to work.
    #
    # Needs hammerspoon: it is drawn by an hs.canvas dropped into the extras
    # loader, and there is no second implementation for a machine without it.
    panel = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Always-visible Todoist panel docked to a screen edge.";
      };

      width = lib.mkOption {
        type = lib.types.int;
        default = 300;
        description = "Panel width in points.";
      };

      screen = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "DELL U2720Q";
        description = ''
          Which monitor to dock to, as an hs.screen.find pattern (name, UUID, or
          id). null uses the primary screen. An unattached screen falls back to
          primary rather than taking the panel away.
        '';
      };
    };
  };

  home =
    {
      cfg,
      userCfg,
      ...
    }:
    let
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

      # Both halves required: the panel IS an hs.canvas, so without hammerspoon
      # there is nothing to draw it and the option would silently do nothing.
      panelEnabled = cfg.panel.enable && userCfg.hammerspoon.enable;
    in
    {
      # Outbound integration, per the repo rule: todoist is the module that
      # knows what a task is, so it reaches into hammerspoon rather than the
      # other way round. init.lua's extras loader picks the file up on its next
      # reload, and hammerspoon stays unaware that todoist exists.
      home.file.".hammerspoon/extras/todoist-panel.lua" = lib.mkIf panelEnabled {
        # Prepended rather than templated through the body: the .lua stays valid
        # on its own — it falls back to these same defaults when the prelude is
        # absent — so nvim, luac and a bare `hs.dofile` can all still read the
        # file in place.
        text = ''
          _G.__todoistPanelCfg = {
            -- Limi ships the rows (todoist-panel-data) on its profile's bin/.
            data = "${inputs.limi.lib.host.profile}/bin/todoist-panel-data",
            width = ${toString cfg.panel.width},
            screen = ${if cfg.panel.screen == null then "nil" else ''"${cfg.panel.screen}"''},
          }
        ''
        + builtins.readFile ./todoist-panel.lua;
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
    };
}
