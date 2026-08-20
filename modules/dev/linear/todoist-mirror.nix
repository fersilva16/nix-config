# Mirror the Linear issues on your plate into Todoist, one way.
#
# This reads Linear's *state*, never its creation events. An issue put there by
# `lin ai`, by Linear's own AI, from the web app, or from Slack all look
# identical from here, because the only question asked is "what is assigned to
# me and not closed". Hooking a creation path instead — `lin create`, `wtl` —
# would mirror only the issues that happened to be born in a terminal, which is
# the subset that needs Todoist least.
#
# The identifier is the join key and it lives in the task content
# ("ENG-123 Fix input sizing"), which makes Todoist its own state store. No
# mapping file to drift out of sync with reality, nothing to rebuild when it
# does, and a task you reworded on the phone still matches as long as the
# prefix survives.
#
# Direction is Linear -> Todoist only. Completing the task in Todoist does not
# touch Linear; the next run notices Linear still has it open and puts it back.
# Closing the loop the other way is a genuinely different feature — it needs to
# tell "I finished this" apart from "I tidied my list" — and is not this.
#
# The close path is the only half that can destroy something, and the first real
# run exercises none of it (nothing is mirrored yet). ./todoist-mirror-test.sh
# pins that logic against fixtures — run it after touching the jq filters.
{
  pkgs,
  lib,
  linear-cli,
}:
let
  # Todoist API v1 answers { results, next_cursor }, but the CLI may already
  # have unwrapped it. Written as an explicit type test rather than
  # `.results // .`: indexing an ARRAY with a string key is a jq error, not a
  # null, so the shorthand makes a bare-array response fail outright. Same
  # reasoning, same shapes as modules/cli/todoist.nix.
  unwrap = ''(if type == "array" then . else (.results // []) end)'';
  wellFormed = ''type == "array" or (type == "object" and has("results"))'';

  # td is a homebrew binary and writeShellApplication resets PATH to
  # runtimeInputs only — without this the sync silently finds no `td`.
  brewBin = "/opt/homebrew/bin";

  mirror = pkgs.writeShellApplication {
    name = "linear-todoist-mirror";
    runtimeInputs = with pkgs; [
      jq
      coreutils
      gnugrep
      linear-cli
    ];
    text = ''
      PATH="${brewBin}:''${PATH}"

      dry=0
      project="Inbox"
      while [ $# -gt 0 ]; do
        case "$1" in
          --dry-run) dry=1 ;;
          --project) project="''${2:-}"; shift ;;
          -h|--help)
            echo "usage: linear-todoist-mirror [--dry-run] [--project NAME]"
            exit 0
            ;;
          *) echo "linear-todoist-mirror: unknown argument: $1" >&2; exit 2 ;;
        esac
        shift
      done

      # `lin list` resolves the display name first; the literal string "me" is
      # not a valid --assignee and silently returns an empty list, which this
      # script would otherwise read as "nothing is assigned to you".
      me=$(linear-cli whoami --output json --no-pager --quiet 2>/dev/null | jq -r '.name // empty')
      if [ -z "$me" ]; then
        echo "linear-todoist-mirror: not authenticated to Linear" >&2
        exit 1
      fi

      # Linear is the only source of truth here, so anything that is not a JSON
      # array has to stop the run. Read as "nothing assigned", a failed fetch
      # would close every mirrored task in Todoist — the one irreversible thing
      # this script can do.
      if ! linear=$(linear-cli i list --assignee "$me" \
            --filter "state.name!=Done" \
            --filter "state.name!=Canceled" \
            --filter "state.name!=Duplicate" \
            --output json --no-pager --quiet 2>/dev/null); then
        echo "linear-todoist-mirror: could not reach Linear" >&2
        exit 1
      fi
      if ! jq -e 'type == "array"' <<<"$linear" >/dev/null 2>&1; then
        echo "linear-todoist-mirror: unexpected Linear response, refusing to sync" >&2
        exit 1
      fi

      if ! todoist=$(td task list --json --limit 300 2>/dev/null); then
        echo "linear-todoist-mirror: could not reach Todoist — try 'td auth status'" >&2
        exit 1
      fi
      if ! jq -e '${wellFormed}' <<<"$todoist" >/dev/null 2>&1; then
        echo "linear-todoist-mirror: unexpected Todoist response, refusing to sync" >&2
        exit 1
      fi

      # Second fence behind the identifier prefix: only tasks living in the
      # target project are ever considered mirrored, so a personal task can not
      # be closed by this even if you name it like an issue. When the project
      # can not be resolved the prefix is the only rail left, which is why an
      # unresolvable name is a hard stop rather than a fallback to Inbox.
      pid=$(td project list --json 2>/dev/null \
            | jq -r --arg n "$project" '${unwrap} | map(select(.name == $n)) | .[0].id // empty')
      if [ -z "$pid" ]; then
        echo "linear-todoist-mirror: no Todoist project named '$project'" >&2
        exit 1
      fi

      # One extra query rather than a hardcoded slug or a per-issue `i get`:
      # `i list` does not return .url, and the workspace never changes mid-run.
      workspace=$(linear-cli api query '{ organization { urlKey } }' \
                  --output json --no-pager --quiet 2>/dev/null \
                  | jq -r '.data.organization.urlKey // empty')

      open=$(jq -r '.[].identifier' <<<"$linear" | sort -u)
      # grep exits 1 on no match, which is the ordinary first-run state, so the
      # pipeline must not be allowed to kill the script under pipefail.
      mirrored=$(jq -r --arg p "$pid" \
                 '${unwrap} | map(select(.projectId == $p)) | .[].content' <<<"$todoist" \
                 | grep -oE '^[A-Z]+-[0-9]+' | sort -u || true)

      added=0
      skipped=0
      # Heredocs rather than pipes: a piped `while` runs in a subshell and the
      # counters would not survive the loop.
      while read -r id; do
        [ -n "$id" ] || continue
        row=$(jq -c --arg i "$id" 'map(select(.identifier == $i)) | .[0] // empty' <<<"$linear")
        [ -n "$row" ] || continue

        title=$(jq -r '.title // ""' <<<"$row")
        # Linear 1..4 is Urgent..Low and maps straight onto Todoist p1..p4.
        # 0 means "no priority" there and has no Todoist equivalent, so it is
        # left off rather than flattened into p4.
        prio=$(jq -r '(.priority // 0) | if . >= 1 and . <= 4 then "p\(.)" else "" end' <<<"$row")

        args=("$id $title" --project "$project")
        [ -n "$prio" ] && args+=(--priority "$prio")
        [ -n "$workspace" ] && args+=(--description "https://linear.app/$workspace/issue/$id")

        if [ "$dry" -eq 1 ]; then
          printf '  + %s  %s\n' "$id" "$title"
        elif ! td task add "''${args[@]}" >/dev/null 2>&1; then
          # Loudly, and without aborting: one malformed title should not stop
          # the other thirteen issues from landing.
          printf 'linear-todoist-mirror: failed to add %s\n' "$id" >&2
          skipped=$((skipped + 1))
          continue
        fi
        added=$((added + 1))
      done <<EOF
      $(comm -23 <(printf '%s\n' "$open") <(printf '%s\n' "$mirrored"))
      EOF

      closed=0
      while read -r id; do
        [ -n "$id" ] || continue
        tid=$(jq -r --arg i "$id" --arg p "$pid" \
              '${unwrap} | map(select(.projectId == $p and (.content | startswith($i + " ")))) | .[0].id // empty' \
              <<<"$todoist")
        [ -n "$tid" ] || continue

        if [ "$dry" -eq 1 ]; then
          printf '  - %s\n' "$id"
        elif ! td task complete "id:$tid" --quiet >/dev/null 2>&1; then
          printf 'linear-todoist-mirror: failed to close %s\n' "$id" >&2
          continue
        fi
        closed=$((closed + 1))
      done <<EOF
      $(comm -13 <(printf '%s\n' "$open") <(printf '%s\n' "$mirrored"))
      EOF

      n=$(jq -r 'length' <<<"$linear")
      if [ "$dry" -eq 1 ]; then
        printf 'dry run: %d to add, %d to close (%d open in Linear)\n' "$added" "$closed" "$n"
      else
        printf '%s  linear→todoist: %d added, %d closed (%d open)\n' \
          "$(date '+%Y-%m-%d %H:%M:%S')" "$added" "$closed" "$n"
        [ "$skipped" -eq 0 ] || printf 'linear-todoist-mirror: %d failed to add\n' "$skipped" >&2
      fi
    '';
  };
in
{
  # Opt-in. The mirror writes to a task list a human reads every day, so it
  # should never switch itself on as a side effect of enabling the Linear CLI.
  default = false;

  extraOptions = {
    project = lib.mkOption {
      type = lib.types.str;
      default = "Inbox";
      description = "Todoist project the mirrored Linear issues live in.";
    };

    intervalSeconds = lib.mkOption {
      type = lib.types.int;
      default = 900;
      description = "Seconds between mirror runs.";
    };
  };

  # No forPlatform guard: linear-cli's own derivation throws on anything that
  # is not aarch64-darwin, so this module is already darwin-only upstream of
  # here and a platform split would be dead code.
  home =
    { cfg, ... }:
    {
      home.packages = [ mirror ];

      launchd.agents.linear-todoist-mirror = {
        enable = true;
        config = {
          Label = "dev.linear.todoist-mirror";
          ProgramArguments = [
            "${mirror}/bin/linear-todoist-mirror"
            "--project"
            cfg.project
          ];
          # ponytail: deliberately not RunAtLoad. The first run after a rebuild
          # is the one worth watching, so the interval doubles as a window to
          # run it by hand with --dry-run first. Flip this on once the mirror
          # has been boring for a while.
          RunAtLoad = false;
          StartInterval = cfg.intervalSeconds;
          StandardOutPath = "/tmp/linear-todoist-mirror.log";
          StandardErrorPath = "/tmp/linear-todoist-mirror.log";
        };
      };
    };
}
