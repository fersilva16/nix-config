# GitHub PR tracker — a status bar count plus a prefix+P popup for triaging
# review requests.
#
# Two views, one keystroke apart (tab toggles):
#   review   awaiting your review, minus anything you already reviewed
#            → drives the status count, which is hidden entirely at zero
#   mine     your own open PRs, with CI + review state
#
# `review-requested:@me` deliberately includes team-based requests. Nobody here
# @-requests an individual reviewer; review lands on you through CODEOWNERS, so
# a direct-only count (`user-review-requested:@me`) reads 0 or 1 forever and
# would hide the actual queue.
#
# That makes the raw number large, and the ignore list is what makes it
# tractable: `x` appends the PR url to a plain-text file that both views and
# the status count filter against, `u` clears it. Permanent by design — no
# expiry, no "until new activity". A dismissed PR stays dismissed.
{ pkgs }:
let
  # ── shared paths ────────────────────────────────────────────────────────
  # Cache is disposable (TMPDIR, like the session picker's PR cache); the
  # ignore list is not, so it lives in XDG state and survives reboots.
  cache = ''"''${TMPDIR:-/tmp}/tmux-pr.json"'';
  ignoreFile = ''"$HOME/.local/state/tmux-pr/ignored"'';
  viewFile = ''"''${TMPDIR:-/tmp}/tmux-pr.view"'';

  # One request for both lists. Measured cost: 1 point of the 5000/hr GraphQL
  # budget, so even a 60s poll is ~1.2% of it. `gh search prs` cannot do this —
  # its JSON has no reviewDecision and no checks (see cli/cli
  # pkg/search/result.go), which would force a second call per PR.
  tmux-pr-refresh = pkgs.writeShellApplication {
    name = "tmux-pr-refresh";
    bashOptions = [ ];
    runtimeInputs = with pkgs; [
      gh
      jq
      coreutils
    ];
    text = ''
      CACHE=${cache}

      # Claim the slot before the ~1s round trip. The widget ticks every 5s and
      # decides staleness by mtime, so without touching first it would spawn a
      # fresh refresh on every tick for the whole duration of this one.
      touch "$CACHE"

      tmp=$(mktemp) || exit 0
      trap 'rm -f "$tmp"' EXIT

      gh api graphql \
        -f query='
          query {
            review: search(query: "is:open is:pr review-requested:@me archived:false", type: ISSUE, first: 100) {
              nodes { ...pr }
            }
            mine: search(query: "is:open is:pr author:@me archived:false", type: ISSUE, first: 100) {
              nodes { ...pr }
            }
          }
          fragment pr on PullRequest {
            repository { nameWithOwner }
            number
            title
            isDraft
            updatedAt
            url
            author { login }
            reviewDecision
            statusCheckRollup { state }
            viewerLatestReview { state }
          }' \
        --jq '
          def norm: {
            repo:   .repository.nameWithOwner,
            number: .number,
            title:  .title,
            author: (.author.login // ""),
            updated: .updatedAt,
            url:    .url,
            draft:  .isDraft,
            decision: (.reviewDecision // ""),
            ci:     (.statusCheckRollup.state // "")
          };
          # Drop anything you have already reviewed. A team review request does
          # not always clear when one member reviews, so these linger in the
          # search results long after the ball left your court.
          # viewerLatestReview is the authoritative per-viewer field; the
          # the -reviewed-by:@me search qualifier answers the same question via
          # the eventually-consistent search index, which is the failure mode
          # session-picker.nix already got burned by.
          # PENDING is an unsubmitted draft review and DISMISSED means the
          # review no longer counts — both still need you, so both stay.
          def awaiting_me:
            .viewerLatestReview == null
            or (.viewerLatestReview.state | IN("PENDING", "DISMISSED"));
          {
            review: [ .data.review.nodes[] | select(awaiting_me) | norm ],
            mine:   [ .data.mine.nodes[]   | norm ]
          }' >"$tmp" 2>/dev/null

      # Only publish a well-formed, non-empty result. A network blip or an
      # expired token otherwise blanks the status bar, which reads exactly like
      # "you have no review requests" — the one lie this must never tell.
      if [ -s "$tmp" ] && jq -e 'has("review")' "$tmp" >/dev/null 2>&1; then
        mv "$tmp" "$CACHE"
      fi
    '';
  };

  # Status segment. Runs every status-interval (5s), so it only ever reads the
  # cache — the GitHub call happens detached, behind an mtime check.
  tmux-pr-widget = pkgs.writeShellApplication {
    name = "tmux-pr-widget";
    bashOptions = [ ];
    runtimeInputs = with pkgs; [
      jq
      findutils
    ];
    text = ''
      CACHE=${cache}
      IGNORE=${ignoreFile}

      # Flexoki light theme colors (same palette as the cpu/disk widgets)
      BG="#f2f0e5"
      FG="#100f0f"

      RESET="#[fg=''${FG},bg=''${BG},nobold,noitalics,nounderscore,nodim]"

      # nf-fa-github, written as an escape rather than pasted in. A bare U+F09B
      # in source is invisible in every diff and review, and survives only until
      # some tool in the chain normalises it away — which is exactly how this
      # widget first shipped with two blank spaces where the icon should be.
      GH=$'\uF09B'

      # ponytail: tmux's own 5s tick is the poll timer. A launchd agent would
      # also poll GitHub at 3am with no tmux running to show the result.
      # Detached, and stdout closed — status-right captures this widget with
      # $(), which would otherwise block until the child exits.
      if ! find "$CACHE" -mmin -2 2>/dev/null | grep -q .; then
        ${tmux-pr-refresh}/bin/tmux-pr-refresh >/dev/null 2>&1 &
      fi

      [ -f "$CACHE" ] || exit 0

      n=$(jq -r --arg ign "$(cat "$IGNORE" 2>/dev/null)" '
        ($ign | split("\n") | map(select(length > 0))) as $ign
        | .review | map(select(.url as $u | $ign | index($u) | not)) | length
      ' "$CACHE" 2>/dev/null) || exit 0

      case "''${n:-}" in "" | *[!0-9]*) exit 0 ;; esac

      # Silent at zero, like the disk widget: an empty queue is not news, and a
      # segment that is always on screen is a segment you stop seeing. Ignoring
      # the last PR therefore clears the slot entirely, which is the point of
      # ignoring it.
      [ "$n" -gt 0 ] || exit 0

      # Black rather than a threshold colour: this is a thing you scan for on
      # purpose, not an alarm that should compete with cpu and disk.
      echo "#[fg=''${FG},bg=''${BG},bold] ''${GH} ''${n}''${RESET} "
    '';
  };

  tmux-pr-pick = pkgs.writeShellApplication {
    name = "tmux-pr-pick";
    bashOptions = [ ];
    runtimeInputs = with pkgs; [
      fzf
      jq
      gh
      coreutils
    ];
    text = ''
      CACHE=${cache}
      IGNORE=${ignoreFile}
      VIEW=${viewFile}

      self="$0"
      view=$(cat "$VIEW" 2>/dev/null) || true
      case "$view" in review | mine) ;; *) view=review ;; esac

      # ── row rendering ─────────────────────────────────────────────────────
      # Emits "<url>\t<display>"; fzf shows field 2 and the binds consume {1}.
      # @tsv escapes tab/newline/backslash only, so the ANSI escapes below
      # survive it intact.
      render() {
        jq -r --arg ign "$(cat "$IGNORE" 2>/dev/null)" --arg view "$1" '
          ($ign | split("\n") | map(select(length > 0))) as $ign

          | def dim: "\u001b[2m"  + . + "\u001b[0m";
            def red: "\u001b[31m" + . + "\u001b[0m";
            def grn: "\u001b[32m" + . + "\u001b[0m";
            def yel: "\u001b[33m" + . + "\u001b[0m";

            def age:
              (now - (.updated | fromdateiso8601)) as $s
              | if   $s < 3600  then "\(($s / 60)    | floor)m"
                elif $s < 86400 then "\(($s / 3600)  | floor)h"
                else                 "\(($s / 86400) | floor)d" end;

            # CI and review state only carry meaning on your own PRs; on the
            # review queue they describe someone elses work, not your action.
            def ci:
              if   .ci == "SUCCESS" then "✓" | grn
              elif .ci == "PENDING" then "•" | yel
              elif .ci == ""        then ""
              else                       "✗" | red end;

            def decision:
              if   .decision == "APPROVED"          then "⇧" | grn
              elif .decision == "CHANGES_REQUESTED" then "±" | red
              else                                       "" end;

          .[$view]
          | map(select(.url as $u | $ign | index($u) | not))
          | sort_by(.updated) | reverse
          | .[]
          | [ .url,
              ( ((.repo | split("/") | last) + "#" + (.number | tostring) | dim)
                + "  " + (if .draft then ("draft " | dim) else "" end)
                + .title
                + "  "
                + (if $view == "mine"
                   then ([ci, decision] | map(select(length > 0)) | join(""))
                   else ("@" + .author | dim) end)
                + "  " + (age | dim) )
            ]
          | @tsv
        ' "$CACHE" 2>/dev/null
      }

      # fzf's header is a plain string, so mark the active view rather than
      # rebuilding a widget: "[review 74] · mine 1".
      header_line() {
        local v="$1" counts r m
        local parts=()
        counts=$(jq -r --arg ign "$(cat "$IGNORE" 2>/dev/null)" '
          ($ign | split("\n") | map(select(length > 0))) as $ign
          | def live: map(select(.url as $u | $ign | index($u) | not)) | length;
            [ (.review | live), (.mine | live) ] | @tsv
        ' "$CACHE" 2>/dev/null) || counts=""
        IFS=$'\t' read -r r m <<<"$counts"
        for pair in "review:''${r:-0}" "mine:''${m:-0}"; do
          local nm="''${pair%%:*}" n="''${pair##*:}"
          if [ "$nm" = "$v" ]; then parts+=("[$nm $n]"); else parts+=("$nm $n"); fi
        done
        printf '%s · %s\n' "''${parts[@]}"
        printf 'enter open · x ignore · u unignore all · tab view · r refresh\n'
      }

      # ── subcommands driven by fzf binds ──────────────────────────────────
      case "''${1:-}" in
        --list)
          render "$view"
          exit 0
          ;;
        --header)
          header_line "$view"
          exit 0
          ;;
        --cycle)
          case "$view" in
            review) next=mine ;;
            *) next=review ;;
          esac
          printf '%s' "$next" >"$VIEW" 2>/dev/null || true
          # transform: emit the follow-up actions for fzf to run. The header
          # goes through transform-header rather than a baked change-header
          # string, so counts can never disagree with the rows next to them.
          printf 'reload(%s --list)+transform-header(%s --header)+first' "$self" "$self"
          exit 0
          ;;
        --ignore)
          [ -n "''${2:-}" ] || exit 0
          mkdir -p "$(dirname "$IGNORE")" 2>/dev/null || true
          printf '%s\n' "$2" >>"$IGNORE"
          exit 0
          ;;
        --unignore-all)
          mkdir -p "$(dirname "$IGNORE")" 2>/dev/null || true
          : >"$IGNORE" 2>/dev/null || true
          exit 0
          ;;
        --open)
          [ -n "''${2:-}" ] || exit 0
          # gh resolves a PR url directly, so this needs no platform-specific
          # opener and no cwd inside the repo.
          gh pr view --web "$2" >/dev/null 2>&1 || true
          exit 0
          ;;
      esac

      # Always open on the review queue: that is the view the status count
      # refers to, and prefix+P is a reflex. Tabbing to your own PRs and
      # closing should not leave them in front of the next reflex. The view
      # file only carries state between fzf's transform binds, not between
      # opens.
      view=review
      printf '%s' "$view" >"$VIEW" 2>/dev/null || true

      # Cold cache: fetch synchronously so the first open shows data instead of
      # an empty box. Every later open reads whatever the status widget last
      # refreshed, so this branch is effectively first-run only.
      [ -f "$CACHE" ] || ${tmux-pr-refresh}/bin/tmux-pr-refresh

      list=$(render "$view")
      if [ -z "$list" ]; then
        list=$'\t'"$(printf '\033[2mnothing here\033[0m')"
      fi

      # Every bind that changes what is on screen re-runs --header too: the
      # counts live in the header, so a reload without it leaves fzf claiming
      # "review 74" over an empty list.
      redraw='reload('"$self"' --list)+transform-header('"$self"' --header)'
      # shellcheck disable=SC2016  # {1} is fzf's placeholder, not a shell var
      b_open='execute-silent('"$self"' --open {1})'
      # shellcheck disable=SC2016
      b_ignore='execute-silent('"$self"' --ignore {1})+'"$redraw"
      b_unignore='execute-silent('"$self"' --unignore-all)+'"$redraw"
      b_refresh='execute-silent(${tmux-pr-refresh}/bin/tmux-pr-refresh)+'"$redraw"

      printf '%s\n' "$list" | fzf \
        --ansi --no-sort --layout=reverse --cycle \
        --delimiter='\t' --with-nth=2 \
        --prompt='❯ ' \
        --info=inline-right \
        --pointer='▶' \
        --gutter=' ' \
        --color='pointer:green,prompt:green,info:dim,header:dim' \
        --header="$(header_line "$view")" \
        --bind "enter:$b_open" \
        --bind "x:$b_ignore" \
        --bind "u:$b_unignore" \
        --bind "r:$b_refresh" \
        --bind "tab:transform:$self --cycle" \
        --bind 'ctrl-c:abort' \
        --bind 'esc:abort'
    '';
  };
in
{
  home = {
    home.packages = [
      tmux-pr-refresh
      tmux-pr-widget
      tmux-pr-pick
    ];

    # 45 keeps PRs left of cpu (50) and disk (55): attention items first.
    xdg.configFile."tmux/widgets/45-pr" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        exec ${tmux-pr-widget}/bin/tmux-pr-widget "$@"
      '';
    };

    programs.tmux.extraConfig = ''
      # GitHub PR triage popup. prefix+P — g/G are the group binds, s/S the
      # session pickers, and lowercase p stays tmux's previous-window.
      bind-key P display-popup -E -w 80% -h 60% '${tmux-pr-pick}/bin/tmux-pr-pick'
    '';
  };
}
