# GitHub PR tracker — a status bar count plus a prefix+P popup over your own
# PR activity.
#
# Three views, one keystroke apart (tab cycles):
#   mine      your open PRs, with CI + review state
#             → drives the status count (see the widget for what it counts)
#   reviewed  PRs by others you submitted a review on in the last 14 days
#   merged    your PRs merged in the last 14 days
#
# 14 days is one sprint's worth of history: long enough to answer "what did I
# ship / review since the last planning", short enough that each list stays a
# screenful inside the single GraphQL request below.
#
# The snooze list hides a PR for as long as its updatedAt still matches: `x`
# records the PR url together with its current updatedAt, and every view and
# the status count skip it until something moves the PR — a new commit, a
# comment, a CI rerun, draft→ready — at which point it resurfaces by itself.
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

  # An open PR of yours needs you when it is red: CI failed or a reviewer asked
  # for changes. Drafts are excluded — a red draft is work in progress, not a
  # signal. Shared by the status count and the popup's highlight so the two can
  # never disagree about which PRs the number means.
  jqAttention = ''
    def attention:
      (.draft | not)
      and ((.ci | IN("FAILURE", "ERROR")) or .decision == "CHANGES_REQUESTED");
  '';

  # Every list selects these fields and normalises them the same way. `gh
  # search prs` cannot stand in for this — its JSON has no reviewDecision and
  # no checks (see cli/cli pkg/search/result.go), which would force a second
  # call per PR.
  gqlBase = ''
    fragment base on PullRequest {
      repository { nameWithOwner }
      number
      title
      isDraft
      state
      updatedAt
      mergedAt
      url
      author { login }
      viewerLatestReview { state submittedAt }
    }
  '';

  # CI and review state only for your open PRs, the one view that shows them.
  # They are the expensive fields: paging the ~500 reviewed candidates took 26s
  # with them and 10s without.
  gqlPr = ''
    fragment pr on PullRequest {
      ...base
      reviewDecision
      statusCheckRollup { state }
    }
  '';

  # `at` is the timestamp each view sorts and ages by: last activity for open
  # PRs, your review for reviewed ones, the merge for merged ones.
  jqNorm = ''
    def norm($at): {
      repo:   .repository.nameWithOwner,
      number: .number,
      title:  .title,
      author: (.author.login // ""),
      updated: .updatedAt,
      at:     $at,
      url:    .url,
      draft:  .isDraft,
      state:  .state,
      decision: (.reviewDecision // ""),
      ci:     (.statusCheckRollup.state // ""),
      review: (.viewerLatestReview.state // "")
    };
  '';

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

      # Local midnight 14 days ago, rendered as UTC. The inner date stamps
      # local midnight with its offset; the outer one converts that instant to
      # Z. Z rather than the offset form because GitHub accepts either, while jq
      # only compares timestamps correctly when both sides share a shape, and
      # submittedAt always comes back as Z.
      # Exported because gh's --jq takes no --arg, and jq's env is the one way
      # into that program without splicing shell into a quoted jq body.
      PR_SINCE=$(date -u -d "$(date -d '14 days ago' +%Y-%m-%dT00:00:00%:z)" +%Y-%m-%dT%H:%M:%SZ)
      export PR_SINCE

      # Claim the slot before the ~1s round trip. The widget ticks every 5s and
      # decides staleness by mtime, so without touching first it would spawn a
      # fresh refresh on every tick for the whole duration of this one.
      touch "$CACHE"

      tmp=$(mktemp) || exit 0
      rev=$(mktemp) || exit 0
      out=$(mktemp) || exit 0
      trap 'rm -f "$tmp" "$rev" "$out"' EXIT

      # The $-names inside the quoted bodies below are GraphQL and jq
      # variables, not shell ones, and single quotes are exactly what keeps
      # bash out of them.
      # shellcheck disable=SC2016
      gh api graphql \
        -f mergedQuery="is:pr is:merged author:@me merged:>=$PR_SINCE archived:false" \
        -f query='
          query($mergedQuery: String!) {
            mine: search(query: "is:open is:pr author:@me archived:false", type: ISSUE, first: 100) {
              nodes { ...pr }
            }
            # ponytail: one page. About 50 merges in 14 days when this shipped;
            # paginate it like the reviewed search if that ever passes 100.
            merged: search(query: $mergedQuery, type: ISSUE, first: 100) {
              nodes { ...base }
            }
          }
          ${gqlPr}
          ${gqlBase}' \
        --jq '
          ${jqNorm}
          {
            mine:   [ .data.mine.nodes[]   | norm(.updatedAt) ],
            merged: [ .data.merged.nodes[] | norm(.mergedAt) ]
          }' >"$tmp" 2>/dev/null || exit 0

      # GitHub has no "reviewed on" qualifier, so the search is only the
      # candidate net: submitting a review bumps updatedAt, which makes
      # updated:>= a superset of the answer — about four times its size, since
      # any later activity on a PR you reviewed long ago matches too.
      # viewerLatestReview.submittedAt is the actual cut, and null while a
      # review is still an unsubmitted draft, which correctly scores as not
      # reviewed yet. Over 100 real reviews land in 14 days, so unlike the
      # lists above this one paginates; --jq runs per page, one PR per line.
      #
      # Lexical >=, which is a real time comparison only because both sides
      # are fixed-width UTC Z — what PR_SINCE goes to the trouble of
      # guaranteeing. Deliberately not fromdate: that builtin parses
      # %Y-%m-%dT%H:%M:%SZ and nothing else, so the offset form errors out.
      # shellcheck disable=SC2016
      gh api graphql --paginate \
        -f reviewedQuery="is:pr reviewed-by:@me -author:@me updated:>=$PR_SINCE archived:false" \
        -f query='
          query($reviewedQuery: String!, $endCursor: String) {
            search(query: $reviewedQuery, type: ISSUE, first: 100, after: $endCursor) {
              nodes { ...base }
              pageInfo { hasNextPage endCursor }
            }
          }
          ${gqlBase}' \
        --jq '
          ${jqNorm}
          .data.search.nodes[]
          | (.viewerLatestReview.submittedAt // null) as $at
          | select($at != null and $at >= env.PR_SINCE)
          | norm($at)' >"$rev" 2>/dev/null || exit 0

      # Only publish a well-formed result. A network blip or an expired token
      # otherwise blanks the status bar, which reads exactly like "nothing
      # needs you" — the one lie this must never tell. Both calls above exit
      # before this point on failure, so an empty $rev here means no reviews.
      # unique_by because the search index can shift between pages and hand
      # the same PR back twice.
      if jq -e 'has("mine") and has("merged")' "$tmp" >/dev/null 2>&1 &&
        jq -s --slurpfile base "$tmp" '$base[0] + { reviewed: unique_by(.url) }' "$rev" >"$out" 2>/dev/null; then
        mv "$out" "$CACHE"
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

      # Your open PRs that need you: failing CI or changes requested. Snoozed
      # PRs never count, whatever the popup happens to be showing: `s` is a way
      # to look at them, not a way to wake them.
      n=$(jq -r --arg ign "$(cat "$IGNORE" 2>/dev/null)" '
        ${jqIgnore}
        ${jqAttention}
        .mine | live | map(select(attention)) | length
      ' "$CACHE" 2>/dev/null) || exit 0

      case "''${n:-}" in "" | *[!0-9]*) exit 0 ;; esac

      # Silent at zero, like the disk widget: nothing red is not news, and a
      # segment that is always on screen is a segment you stop seeing.
      [ "$n" -eq 0 ] && exit 0

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
      git
      fish
    ];
    text = ''
      CACHE=${cache}
      IGNORE=${ignoreFile}
      VIEW=${viewFile}
      SHOW=${showFile}

      self="$0"
      view=$(cat "$VIEW" 2>/dev/null) || true
      case "$view" in mine | reviewed | merged) ;; *) view=mine ;; esac
      show=$(cat "$SHOW" 2>/dev/null) || true
      case "$show" in 1) ;; *) show="" ;; esac

      # ── row rendering ─────────────────────────────────────────────────────
      # Emits "<url>\t<display>"; fzf shows field 2 and the binds consume {1}.
      # @tsv escapes tab/newline/backslash only, so the ANSI escapes below
      # survive it intact.
      render() {
        jq -r --arg ign "$(cat "$IGNORE" 2>/dev/null)" --arg view "$1" --arg show "$2" '
          ${jqIgnore}
          ${jqAttention}

            def dim: "\u001b[2m"  + . + "\u001b[0m";
            def red: "\u001b[31m" + . + "\u001b[0m";
            def grn: "\u001b[32m" + . + "\u001b[0m";
            def yel: "\u001b[33m" + . + "\u001b[0m";
            def mag: "\u001b[35m" + . + "\u001b[0m";

            def age:
              (now - ((.at // .updated) | fromdateiso8601)) as $s
              | if   $s < 3600  then "\(($s / 60)    | floor)m"
                elif $s < 86400 then "\(($s / 3600)  | floor)h"
                else                 "\(($s / 86400) | floor)d" end;

            def ci:
              if   .ci == "SUCCESS" then "✓" | grn
              elif .ci == "PENDING" then "•" | yel
              elif .ci == ""        then ""
              else                       "✗" | red end;

            def decision:
              if   .decision == "APPROVED"          then "⇧" | grn
              elif .decision == "CHANGES_REQUESTED" then "±" | red
              else                                       "" end;

            # Your verdict on someone elses PR, plus where that PR ended up:
            # a review you approved that has since merged is done, one still
            # open may be waiting on you again.
            def my_review:
              if   .review == "APPROVED"          then "approved" | grn
              elif .review == "CHANGES_REQUESTED" then "changes"  | red
              else                                     "commented" | dim end;
            def pr_state:
              if   .state == "MERGED" then "merged" | mag
              elif .state == "CLOSED" then "closed" | dim
              else                         "open"   | dim end;

            def suffix:
              if   $view == "mine"
                then [ci, decision] | map(select(length > 0)) | join("")
              elif $view == "reviewed"
                then my_review + " " + pr_state + "  " + ("@" + .author | dim)
              else ""
              end;

          .[$view]
          | (if $show == "1" then . else live end)
          | sort_by(.at // .updated) | reverse | .[]
          | [ .url,
              ( ( ((.repo | split("/") | last) + "#" + (.number | tostring) | dim)
                  + "  " + (if .draft then ("draft " | dim) else "" end)
                  + (if $view == "mine" and attention then ("● " | red) else "" end)
                  + .title
                  + "  " + suffix
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
      # rebuilding a widget: "[mine 6] · reviewed 12 · merged 9 · 1 snoozed".
      header_line() {
        local v="$1" s="$2" counts m rv mg z tail=""
        local parts=()
        counts=$(jq -r --arg ign "$(cat "$IGNORE" 2>/dev/null)" --arg view "$v" '
          ${jqIgnore}
          [ (.mine     | live | length),
            (.reviewed | live | length),
            (.merged   | live | length),
            (.[$view] | map(select(snoozed)) | length) ] | @tsv
        ' "$CACHE" 2>/dev/null) || counts=""
        IFS=$'\t' read -r m rv mg z <<<"$counts"
        for pair in "mine:''${m:-0}" "reviewed:''${rv:-0}" "merged:''${mg:-0}"; do
          local nm="''${pair%%:*}" n="''${pair##*:}"
          if [ "$nm" = "$v" ]; then parts+=("[$nm $n]"); else parts+=("$nm $n"); fi
        done
        # The snoozed tally only earns header space when it is non-zero, and it
        # has to say whether those rows are on screen: a dimmed row and a hidden
        # row are indistinguishable if you cannot tell which mode you are in.
        if [ "''${z:-0}" -gt 0 ]; then
          if [ -n "$s" ]; then tail=" · $z snoozed shown"; else tail=" · $z snoozed"; fi
        fi
        printf '%s · %s · %s%s\n' "''${parts[@]}" "$tail"
        printf 'enter open · w worktree · x snooze · s show · u clear · / search · tab view · r refresh · last 14d\n'
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
            mine) next=reviewed ;;
            reviewed) next=merged ;;
            *) next=mine ;;
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
            ([.mine[], .reviewed[], .merged[]] | map(select(.url == $u)) | .[0].updated) // ""
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
          # The row already carries the url, so opening it needs nothing from
          # the GitHub API — but routing it through `gh` did. During a GitHub
          # 503 every enter press became a silent no-op, because the failure
          # is deliberately swallowed so a dead opener cannot kill the popup.
          # The desktop opener has no network in its path; gh stays only as
          # the fallback for hosts without one.
          open "$2" >/dev/null 2>&1 || gh pr view --web "$2" >/dev/null 2>&1 || true
          exit 0
          ;;
        --worktree)
          # Hand the PR to wtpr. wtpr resolves a bare number against the repo
          # it runs in, while this popup spans every repo, so first find the
          # local clone whose origin is the PR's repo. Matched by remote, not
          # by directory name: clones live at ~/<name> and ~/<org>/<name>, and
          # the directory does not always carry the repo's name. Only real
          # .git dirs count — a worktree's .git is a file, and wtpr finds the
          # main checkout on its own anyway.
          url="''${2:-}"
          case "$url" in https://github.com/*/pull/*) ;; *) exit 0 ;; esac
          rest=''${url#https://github.com/}
          repo=''${rest%/pull/*}
          num=''${rest##*/}
          case "$num" in "" | *[!0-9]*) exit 0 ;; esac

          dir=""
          for g in "$HOME"/*/.git "$HOME"/*/*/.git; do
            [ -d "$g" ] || continue
            r=$(git -C "''${g%/.git}" remote get-url origin 2>/dev/null) || continue
            r=''${r%.git}
            r=''${r%/}
            r=''${r#*github.com[:/]}
            if [ "''${r,,}" = "''${repo,,}" ]; then
              dir=''${g%/.git}
              break
            fi
          done
          if [ -z "$dir" ]; then
            printf 'no local clone of %s in ~/* or ~/*/*\n' "$repo"
            read -rsn1 -p 'press any key' </dev/tty || true
            exit 0
          fi

          # wt names the new session <parent>/<name> after the session it runs
          # from, which from this popup is whatever repo you happened to be
          # in. Session groups follow the first directory under ~ instead —
          # ~/telepatia/monobloco is "telepatia", ~/nix-config is
          # "nix-config". Derived from the path rather than read off tmux:
          # scanning panes for one inside the repo picked whichever session
          # had last cd'd there, and the first misnamed session then won
          # every lookup after it.
          rel=''${dir#"$HOME"/}
          parent=''${rel%%/*}

          # wtpr prompts for the worktree name, so it needs the terminal, not
          # the pipe fzf was fed from. On success it switches the client and
          # the popup closes with it; on failure keep its error on screen.
          cd "$dir" || exit 0
          WT_PARENT_SESSION="$parent" fish -c "wtpr $num" </dev/tty && exit 0
          read -rsn1 -p 'press any key' </dev/tty || true
          exit 0
          ;;
      esac

      # Always open on your own PRs with snoozed rows folded away: that is what
      # the status count refers to, and prefix+P is a reflex. Tabbing to the
      # history views, or peeking at the snoozed pile, should not leave either
      # in front of the next reflex. Both state files only carry state between
      # fzf's transform binds, not between opens.
      view=mine
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
      # "mine 6" over an empty list.
      redraw='reload('"$self"' --list)+transform-header('"$self"' --header)'
      # shellcheck disable=SC2016  # {1} is fzf's placeholder, not a shell var
      b_open='execute-silent('"$self"' --open {1})'
      # shellcheck disable=SC2016
      b_worktree='become('"$self"' --worktree {1})'
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
      b_search='unbind(change)+unbind(w)+unbind(x)+unbind(s)+unbind(u)+unbind(r)+unbind(/)+clear-query+change-prompt(/ )+enable-search'
      # Back to menu mode: reload repopulates the full list, since disable-search
      # on its own freezes whatever subset the last query left behind.
      b_esc_back='clear-query+disable-search+change-prompt(❯ )+rebind(change)+rebind(w)+rebind(x)+rebind(s)+rebind(u)+rebind(r)+rebind(/)+'"$redraw"
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
        --bind "w:$b_worktree" \
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
      # GitHub PR popup. prefix+P — s/S are the session pickers, and
      # lowercase p stays tmux's previous-window.
      bind-key P display-popup -E -w 80% -h 60% '${tmux-pr-pick}/bin/tmux-pr-pick'
    '';
  };
}
