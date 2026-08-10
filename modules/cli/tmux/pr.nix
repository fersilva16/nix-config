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
# That makes the raw number large, and the snooze list is what makes it
# tractable: `x` records the PR url together with its current updatedAt, and
# both views and the status count hide it for as long as that timestamp still
# matches. Anything that moves the PR — a new commit, a comment, draft→ready —
# bumps updatedAt, so a snoozed PR resurfaces by itself the moment it is worth
# looking at again.
#
# Hiding without recall is just a slower way to lose a PR, so `s` folds the
# snoozed ones back in, dimmed, and `x` on one of those wakes it up. `u` is the
# nuclear option and clears the list outright.
{ pkgs }:
let
  # ── shared paths ────────────────────────────────────────────────────────
  # Cache is disposable (TMPDIR, like the session picker's PR cache); the
  # snooze list is not, so it lives in XDG state and survives reboots.
  cache = ''"''${TMPDIR:-/tmp}/tmux-pr.json"'';
  ignoreFile = ''"$HOME/.local/state/tmux-pr/ignored"'';
  viewFile = ''"''${TMPDIR:-/tmp}/tmux-pr.view"'';
  showFile = ''"''${TMPDIR:-/tmp}/tmux-pr.show"'';

  # Every snooze-aware query shares this prelude. The file is one
  # "<url>\t<updatedAt>" per line; from_entries makes the last line for a url
  # win, which is what re-snoozing an updated PR should do.
  #
  # A line with no tab — the old format — carries an empty timestamp and never
  # expires, so PRs dismissed under the previous scheme stay dismissed instead
  # of all flooding back on the first rebuild.
  #
  # ponytail: the file only grows, and `u` is the compaction strategy. A few
  # hundred stale lines cost nothing to parse; prune them if it ever shows up
  # in the 5s widget tick.
  jqIgnore = ''
    ($ign | split("\n") | map(select(length > 0) | split("\t") | { key: .[0], value: (.[1] // "") }) | from_entries) as $ign
    | def snoozed: $ign[.url] as $at | $at != null and ($at == "" or $at == .updated);
      def live: map(select(snoozed | not));
  '';

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

      # The count never counts snoozed PRs, whatever the popup happens to be
      # showing: `s` is a way to look at them, not a way to wake them.
      n=$(jq -r --arg ign "$(cat "$IGNORE" 2>/dev/null)" '
        ${jqIgnore}
        .review | live | length
      ' "$CACHE" 2>/dev/null) || exit 0

      case "''${n:-}" in "" | *[!0-9]*) exit 0 ;; esac

      # Silent at zero, like the disk widget: an empty queue is not news, and a
      # segment that is always on screen is a segment you stop seeing. Snoozing
      # the last PR therefore clears the slot entirely, which is the point of
      # snoozing it.
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
      gawk
      coreutils
    ];
    text = ''
      CACHE=${cache}
      IGNORE=${ignoreFile}
      VIEW=${viewFile}
      SHOW=${showFile}

      self="$0"
      view=$(cat "$VIEW" 2>/dev/null) || true
      case "$view" in review | mine) ;; *) view=review ;; esac
      show=$(cat "$SHOW" 2>/dev/null) || true
      case "$show" in 1) ;; *) show="" ;; esac

      # ── row rendering ─────────────────────────────────────────────────────
      # Emits "<url>\t<display>"; fzf shows field 2 and the binds consume {1}.
      # @tsv escapes tab/newline/backslash only, so the ANSI escapes below
      # survive it intact.
      render() {
        jq -r --arg ign "$(cat "$IGNORE" 2>/dev/null)" --arg view "$1" --arg show "$2" '
          ${jqIgnore}

            def dim: "\u001b[2m"  + . + "\u001b[0m";
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
          | (if $show == "1" then . else live end)
          | sort_by(.updated) | reverse
          | .[]
          | [ .url,
              ( ( ((.repo | split("/") | last) + "#" + (.number | tostring) | dim)
                  + "  " + (if .draft then ("draft " | dim) else "" end)
                  + .title
                  + "  "
                  + (if $view == "mine"
                     then ([ci, decision] | map(select(length > 0)) | join(""))
                     else ("@" + .author | dim) end)
                  + "  " + (age | dim) ) as $row

                # A snoozed row goes fully dim. Wrapping the finished row would
                # not work — its own inner resets end the dim a third of the way
                # in — so strip every SGR code first and re-apply one. Losing
                # the CI colours is the point: a row you already dropped should
                # read as background noise.
                | if snoozed
                  then ($row | gsub("\u001b\\[[0-9;]*m"; "") | dim)
                  else $row end )
            ]
          | @tsv
        ' "$CACHE" 2>/dev/null
      }

      # fzf's header is a plain string, so mark the active view rather than
      # rebuilding a widget: "[review 74] · mine 1 · 3 snoozed".
      header_line() {
        local v="$1" s="$2" counts r m z tail=""
        local parts=()
        counts=$(jq -r --arg ign "$(cat "$IGNORE" 2>/dev/null)" --arg view "$v" '
          ${jqIgnore}
          [ (.review | live | length),
            (.mine   | live | length),
            (.[$view] | map(select(snoozed)) | length) ] | @tsv
        ' "$CACHE" 2>/dev/null) || counts=""
        IFS=$'\t' read -r r m z <<<"$counts"
        for pair in "review:''${r:-0}" "mine:''${m:-0}"; do
          local nm="''${pair%%:*}" n="''${pair##*:}"
          if [ "$nm" = "$v" ]; then parts+=("[$nm $n]"); else parts+=("$nm $n"); fi
        done
        # The snoozed tally only earns header space when it is non-zero, and it
        # has to say whether those rows are on screen: a dimmed row and a hidden
        # row are indistinguishable if you cannot tell which mode you are in.
        if [ "''${z:-0}" -gt 0 ]; then
          if [ -n "$s" ]; then tail=" · $z snoozed shown"; else tail=" · $z snoozed"; fi
        fi
        printf '%s · %s%s\n' "''${parts[@]}" "$tail"
        printf 'enter open · x snooze · s show · u clear · / search · tab view · r refresh\n'
      }

      # ── subcommands driven by fzf binds ──────────────────────────────────
      case "''${1:-}" in
        --list)
          render "$view" "$show"
          exit 0
          ;;
        --header)
          header_line "$view" "$show"
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
        --show-toggle)
          if [ -n "$show" ]; then
            : >"$SHOW" 2>/dev/null || true
          else
            printf '1' >"$SHOW" 2>/dev/null || true
          fi
          exit 0
          ;;
        --snooze)
          [ -n "''${2:-}" ] || exit 0
          mkdir -p "$(dirname "$IGNORE")" 2>/dev/null || true

          # Snooze against the timestamp you are looking at, which is whatever
          # the cache last saw.
          at=$(jq -r --arg u "$2" '
            ([.review[], .mine[]] | map(select(.url == $u)) | .[0].updated) // ""
          ' "$CACHE" 2>/dev/null) || at=""

          # One rule covers both directions: drop every line for this url, then
          # put one back unless the PR was already hidden. That makes `x` a
          # toggle on a dimmed row, while a row that resurfaced on its own is
          # re-snoozed at its new timestamp instead of being woken up.
          # shellcheck disable=SC2016  # awk field refs, not shell positionals
          hidden=$(awk -F'\t' -v u="$2" -v at="$at" '$1 == u && ($2 == "" || $2 == at)' "$IGNORE" 2>/dev/null)
          tmp=$(mktemp) || exit 0
          # shellcheck disable=SC2016
          if awk -F'\t' -v u="$2" '$1 != u' "$IGNORE" >"$tmp" 2>/dev/null; then
            mv "$tmp" "$IGNORE"
          fi
          rm -f "$tmp"

          [ -n "$hidden" ] || printf '%s\t%s\n' "$2" "$at" >>"$IGNORE"
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

      # Always open on the review queue with snoozed rows folded away: that is
      # what the status count refers to, and prefix+P is a reflex. Tabbing to
      # your own PRs, or peeking at the snoozed pile, should not leave either in
      # front of the next reflex. Both state files only carry state between
      # fzf's transform binds, not between opens.
      view=review
      printf '%s' "$view" >"$VIEW" 2>/dev/null || true
      show=""
      : >"$SHOW" 2>/dev/null || true

      # Cold cache: fetch synchronously so the first open shows data instead of
      # an empty box. Every later open reads whatever the status widget last
      # refreshed, so this branch is effectively first-run only.
      [ -f "$CACHE" ] || ${tmux-pr-refresh}/bin/tmux-pr-refresh

      list=$(render "$view" "$show")
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
      b_snooze='execute-silent('"$self"' --snooze {1})+'"$redraw"
      b_show='execute-silent('"$self"' --show-toggle)+'"$redraw"
      b_unignore='execute-silent('"$self"' --unignore-all)+'"$redraw"
      b_refresh='execute-silent(${tmux-pr-refresh}/bin/tmux-pr-refresh)+'"$redraw"

      # Menu mode by default (--disabled), `/` for search — same two modes as
      # the session picker. A bare printable bind wins over typing, so with
      # search live from the start every action key is also a letter you cannot
      # type: "parser" arrived as "pae" while the two r's each fired a
      # synchronous gh round trip and the s toggled the snoozed rows. Unbinding
      # them for the duration of a query is what makes the search box a search
      # box.
      #
      # change:clear-query is the other half. --disabled only stops the query
      # from filtering, it still collects every unbound letter, so menu mode
      # would quietly build up a "pae" in the prompt that looks like a search
      # doing nothing. Wiping it on change keeps the prompt honest; the bind has
      # to come off in search mode or it would eat the query as you type it.
      b_search='unbind(change)+unbind(x)+unbind(s)+unbind(u)+unbind(r)+unbind(/)+clear-query+change-prompt(/ )+enable-search'
      # Back to menu mode: reload repopulates the full list, since disable-search
      # on its own freezes whatever subset the last query left behind.
      b_esc_back='clear-query+disable-search+change-prompt(❯ )+rebind(change)+rebind(x)+rebind(s)+rebind(u)+rebind(r)+rebind(/)+'"$redraw"
      # shellcheck disable=SC2016  # $FZF_PROMPT is fzf's, not bash's
      b_esc='transform~[ "$FZF_PROMPT" = "/ " ] && echo "'"$b_esc_back"'" || echo abort~'

      printf '%s\n' "$list" | fzf \
        --ansi --no-sort --layout=reverse --cycle \
        --delimiter='\t' --with-nth=2 \
        --disabled \
        --prompt='❯ ' \
        --info=inline-right \
        --pointer='▶' \
        --gutter=' ' \
        --color='pointer:green,prompt:green,info:dim,header:dim' \
        --header="$(header_line "$view" "$show")" \
        --bind "enter:$b_open" \
        --bind "x:$b_snooze" \
        --bind "s:$b_show" \
        --bind "u:$b_unignore" \
        --bind "r:$b_refresh" \
        --bind "/:$b_search" \
        --bind 'change:clear-query' \
        --bind "tab:transform:$self --cycle" \
        --bind 'ctrl-c:abort' \
        --bind "esc:$b_esc"
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
