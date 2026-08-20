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

          n=$(jq -r '${unwrap} | length' "$CACHE" 2>/dev/null) || exit 0
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
          PATH="${brewBin}:''${PATH}"
          self="$0"

          render() {
            jq -r '
              def dim: "\u001b[2m" + . + "\u001b[0m";
              def red: "\u001b[31m" + . + "\u001b[0m";
              def grn: "\u001b[32m" + . + "\u001b[0m";
              ${unwrap}
              | .[]
              | [ .id,
                  ( (if (.priority // 1) == 4 then ("! " | red) else "" end)
                    + .content
                    + (if .due then ("  " + ((.due.string // .due.date) | tostring) | grn) else "" end)
                  )
                ]
              | @tsv
            ' "$CACHE" 2>/dev/null
          }

          header_line() {
            local n
            n=$(jq -r '${unwrap} | length' "$CACHE" 2>/dev/null) || n=0
            printf '%s open\n' "''${n:-0}"
            printf 'enter open · x done · a add · r refresh · / search\n'
          }

          case "''${1:-}" in
            --list)
              render
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
              [ -n "''${2:-}" ] || exit 0
              td task complete "id:$2" --quiet >/dev/null 2>&1 || true
              ${tmux-todoist-refresh}/bin/tmux-todoist-refresh
              exit 0
              ;;
            --add)
              # A form rather than one line. quickadd's `p1 #Project` syntax can
              # carry due, priority and project, but nothing in it can carry a
              # description, and the syntax only helps if you remember it. Named
              # fields are the discoverable half; `t <text>` in a pane is still
              # the one-line fast path, so nothing that was quick got slower.
              #
              # Colours are ANSI indices rather than the widget's Flexoki hex:
              # this renders on the terminal's own background and should follow
              # its theme, exactly like the fzf list behind it.
              D=$(printf '\033[2m')
              G=$(printf '\033[32m')
              R=$(printf '\033[31m')
              N=$(printf '\033[0m')
              ICON=$(printf '\uF0AE')

              # Shared by the live prompt and the frozen row, which is the whole
              # trick below — it has to stay a single definition.
              pad() { printf '%s     %-10s%s' "$D" "$1" "$N"; }

              row() {
                [ -n "$2" ] || return 0
                printf '%s%s%s%s\n' "$(pad "$1")" "''${3:-}" "$2" "$N"
              }

              content=""; due=""; prio="none"; project=""; notes=""

              # Redrawn after every answer. Deliberately ends without a trailing
              # blank line: the next gum prompt has to land on the very line its
              # own frozen row will occupy, so a field does not jump when it is
              # committed and the form fills in place.
              draw() {
                printf '\033[2J\033[H'
                printf '\n  %s%s  new task%s\n' "$G" "$ICON" "$N"
                printf '  %s%s%s\n\n' "$D" "──────────────────────────────────────────────" "$N"
                row task "$content"
                row due "$due" "$G"
                [ "$prio" = none ] || row priority "$prio" "$R"
                row project "$project"
                [ -z "$notes" ] || row notes "$(printf '%s' "$notes" | head -n1 | cut -c1-46)"
              }

              # One rule for every field: enter accepts and an empty field is a
              # skip, esc abandons the task. Same esc as the list it opened from.
              draw
              content=$(gum input --prompt "$(pad task)" --no-show-help \
                --placeholder "what needs doing" --width 0 \
                --cursor.foreground 2 --placeholder.foreground 245) || exit 0
              [ -n "$content" ] || exit 0

              draw
              due=$(gum input --prompt "$(pad due)" --no-show-help \
                --placeholder "tomorrow 9am · friday · every monday" --width 0 \
                --cursor.foreground 2 --placeholder.foreground 245) || exit 0

              # label:value, so the list reads as words and still submits `p1`.
              draw
              prio=$(gum choose --header "$(pad priority)" --no-show-help \
                --cursor "  ❯  " --cursor.foreground 2 --selected.foreground 2 \
                --label-delimiter ":" --selected none --height 5 \
                "none:none" "p3 · low:p3" "p2 · medium:p2" "p1 · urgent:p1") || exit 0

              # Skipped when there is nothing to choose between: a single-project
              # account should not be asked where the task goes.
              draw
              pjson=$(td project list --json 2>/dev/null)
              if [ "$(printf '%s' "$pjson" | jq -r '${unwrap} | length' 2>/dev/null || echo 0)" -gt 1 ]; then
                project=$(printf '%s' "$pjson" | jq -r '${unwrap} | .[].name' \
                  | gum choose --header "$(pad project)" --no-show-help \
                      --cursor "  ❯  " --cursor.foreground 2 --selected.foreground 2 \
                      --height 8) || exit 0
              fi

              # The one field quickadd could never carry. show-help stays on here
              # because enter submits and shift+enter makes a newline, which is
              # the only binding in this form you would not already guess.
              draw
              notes=$(gum write --header "$(pad notes)" \
                --placeholder "context, links, the first step…" \
                --prompt "     ┃ " --width 0 --height 5 \
                --cursor.foreground 2 --placeholder.foreground 245) || exit 0

              args=("$content")
              [ -n "$due" ] && args+=(--due "$due")
              [ "$prio" != none ] && args+=(--priority "$prio")
              [ -n "$project" ] && args+=(--project "$project")
              [ -n "$notes" ] && args+=(--description "$notes")

              # Loudly, not with `|| true`: a capture tool that silently drops
              # what you just typed is worse than one that refuses to take it.
              if ! td task add "''${args[@]}" >/dev/null 2>&1; then
                draw
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

          list=$(render)
          if [ -z "$list" ]; then
            list=$(printf '\t\033[2mnothing open\033[0m')
          fi

          redraw='reload('"$self"' --list)+transform-header('"$self"' --header)'
          b_open='execute-silent('"$self"' --open {1})'
          b_done='execute-silent('"$self"' --complete {1})+'"$redraw"
          b_add='execute('"$self"' --add)+'"$redraw"
          b_refresh='execute-silent(${tmux-todoist-refresh}/bin/tmux-todoist-refresh)+'"$redraw"
          b_search='unbind(change)+unbind(x)+unbind(a)+unbind(r)+unbind(/)+clear-query+change-prompt(/ )+enable-search'
          b_esc_back='clear-query+disable-search+change-prompt(> )+rebind(change)+rebind(x)+rebind(a)+rebind(r)+rebind(/)+'"$redraw"
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
            --bind "enter:$b_open" \
            --bind "x:$b_done" \
            --bind "a:$b_add" \
            --bind "r:$b_refresh" \
            --bind "/:$b_search" \
            --bind 'change:clear-query' \
            --bind 'ctrl-c:abort' \
            --bind "esc:$b_esc"
        '';
      };
    in
    {
      home.packages = lib.mkIf userCfg.tmux.enable [
        tmux-todoist-refresh
        tmux-todoist-widget
        tmux-todoist-pick
      ];

      programs.tmux.extraConfig = lib.mkIf userCfg.tmux.enable ''
        # Todoist triage popup. This deliberately overrides tmux's default
        # prefix+t clock-mode: the time is already in the menu bar, on the
        # phone, and on every other surface, so the key is better spent.
        # Matches the shell verb — `t` in a pane, prefix+t in tmux.
        bind-key t display-popup -E -w 80% -h 60% '${tmux-todoist-pick}/bin/tmux-todoist-pick'
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

          if test (count $argv) -eq 0
            # Fetch and parse in two steps so a failed td is distinguishable
            # from an empty list. Piping straight into jq would report jq's
            # exit status, and an expired token would render as "nothing open".
            set -l json (td task list --json --limit 300 2>/dev/null)
            if test $status -ne 0
              echo "t: could not reach Todoist — try 'td auth status'" >&2
              return 1
            end

            set -l rows (printf '%s\n' $json | jq -r '${unwrap} | .[] | [.id, .content, (.due.string // ""), (.priority // 1)] | @tsv')

            if test (count $rows) -eq 0
              echo "  "(set_color green)"✓"(set_color normal)" nothing open"
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
              end
              set -l due ""
              if test -n "$f[3]"
                set due "  "(set_color green)"$f[3]"(set_color normal)
              end
              printf '%s %s%2d%s  %s%s\n' "$mark" (set_color brblack) $i (set_color normal) "$f[2]" "$due"
            end

            set -l n (count $rows)
            if test $n -ge ${toString cfg.warnAt}
              echo "  "(set_color yellow)"$n open — drop what you are not going to do: t rm <n>"(set_color normal)
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
              td task delete "id:$id" --quiet >/dev/null 2>&1
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
