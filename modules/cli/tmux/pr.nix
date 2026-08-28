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
  shapesFile = ''"$HOME/.local/state/tmux-pr/shapes.json"'';
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

  # A review request names the branch it targets, not the PR that made that
  # branch. The six PostHog service migrations consequently arrived as six
  # unrelated diffs until their otherwise-invisible setup PR was included.
  jqTree = ''
    def ref:
      if (.head // "") == "" then null else .repo + "\u0000" + .head end;
    def base_ref:
      if (.base // "") == "" then null else .repo + "\u0000" + .base end;
    def children($nodes; $parent):
      [ $nodes[] | select($parent != null and base_ref == $parent) ]
      | sort_by(.updated) | reverse;
    def tree($nodes; $node; $depth):
      $node as $current
      | ($current + { depth: $depth })
      , (children($nodes; ($current | ref))[] | tree($nodes; .; ($depth + 1)));
    def tree_roots($nodes):
      [ $nodes[]
        | . as $node
        | select(
            (($node | base_ref) as $base
             | ($base != null and ($nodes | any(ref == $base)))
            )
            | not
          )
      ];
    def tree_forest($nodes):
      [ tree_roots($nodes)[] as $root
        | [ tree($nodes; $root; 0) ] as $rows
        | {
            updated: ($rows | map(.updated) | max),
            members: ($rows | length),
            rows: $rows,
            treeRoot: ($root | ref)
          }
      ]
      | sort_by(.updated) | reverse
      | .[]
      | .members as $members
      | .treeRoot as $treeRoot
      | .rows[]
      | . + { members: $members, treeRoot: $treeRoot };
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

      # Local midnight, rendered as UTC: "today" is the day you are having, not
      # the one UTC is having — a bare date would roll the counters over at
      # 21:00 here, which is squarely inside a working evening.
      # The inner date stamps local midnight with its offset; the outer one
      # converts that instant to Z. Both steps are needed: `date -u -d "today
      # 00:00:00"` reads *UTC* midnight and returns a different instant.
      # Z rather than the offset form because GitHub accepts either, while jq
      # only compares timestamps correctly when both sides share a shape, and
      # submittedAt always comes back as Z.
      # Exported because gh's --jq takes no --arg, and jq's env is the one way
      # into that program without splicing shell into a quoted jq body.
      PR_SINCE=$(date -u -d "$(date +%Y-%m-%dT00:00:00%:z)" +%Y-%m-%dT%H:%M:%SZ)
      export PR_SINCE

      # Claim the slot before the ~1s round trip. The widget ticks every 5s and
      # decides staleness by mtime, so without touching first it would spawn a
      # fresh refresh on every tick for the whole duration of this one.
      touch "$CACHE"

      tmp=$(mktemp) || exit 0
      trap 'rm -f "$tmp"' EXIT

      # GitHub's review queue omits the PR which created a stack's base branch.
      # Resolve only those missing bases, repository by repository: branch names
      # repeat across repos often enough that a global lookup manufactures trees.
      resolve_parents() {
        local work state frontier seen next_seen round parents next_state repos bases
        local depth=0 repo branch query term old_count new_count

        work=$(mktemp -d) || return 1
        state="$work/state.json"
        frontier="$work/frontier.json"
        seen="$work/seen.json"
        next_seen="$work/next-seen.json"
        round="$work/round.json"
        parents="$work/parents.json"
        next_state="$work/next-state.json"
        repos="$work/repos"
        bases="$work/bases"

        cp "$tmp" "$state" || {
          rm -rf "$work"
          return 1
        }
        printf '[]' >"$seen"

        fetch_parent_batch() {
          local repo="$1" response="$work/response.json"
          shift

          if ! gh pr list -R "$repo" --state open --limit 100 "$@" \
            --json number,title,isDraft,createdAt,updatedAt,url,author,baseRefName,headRefName \
            >"$response" 2>/dev/null; then
            return 1
          fi
          if ! jq -e 'type == "array"' "$response" >/dev/null 2>&1; then
            return 1
          fi
          jq --arg repo "$repo" '
            [ .[] | {
                repo: $repo,
                number: .number,
                title: .title,
                author: (.author.login // ""),
                created: .createdAt,
                updated: .updatedAt,
                url: .url,
                draft: .isDraft,
                decision: "",
                ci: "",
                base: .baseRefName,
                head: .headRefName,
                context: true
              }
            ]
          ' "$response" >>"$round" || return 1
        }

        # ponytail: ancestry stops after eight hops; raise this ceiling if a
        # real review stack exceeds it, rather than turning every refresh into
        # an unbounded search after a malformed branch cycle.
        while [ "$depth" -lt 8 ]; do
          if ! jq --slurpfile seen "$seen" '
            ($seen[0]) as $seen
            | .review as $known
            | ($known | map(.repo + "\u0000" + .head)) as $heads
            | [ $known[]
                | . as $candidate
                | select($candidate.base != "")
                | select(($heads | index($candidate.repo + "\u0000" + $candidate.base)) | not)
                | { repo: $candidate.repo, base: $candidate.base }
                | . as $candidate
                | select(($seen | index($candidate)) | not)
                | $candidate
              ]
            | unique_by([.repo, .base])
          ' "$state" >"$frontier"; then
            rm -rf "$work"
            return 1
          fi

          if jq -e 'length == 0' "$frontier" >/dev/null 2>&1; then
            break
          fi
          if ! jq -s '.[0] + .[1] | unique' "$seen" "$frontier" >"$next_seen"; then
            rm -rf "$work"
            return 1
          fi
          mv "$next_seen" "$seen"

          : >"$round"
          jq -r '.[].repo' "$frontier" | sort -u >"$repos" || {
            rm -rf "$work"
            return 1
          }
          while IFS= read -r repo; do
            [ -n "$repo" ] || continue
            jq -r --arg repo "$repo" '.[] | select(.repo == $repo) | .base' "$frontier" >"$bases" || {
              rm -rf "$work"
              return 1
            }
            query="is:open"
            while IFS= read -r branch; do
              [ -n "$branch" ] || continue
              term=" head:$branch"
              # GitHub cuts search strings at about 256 bytes. 240 leaves room
              # for its own parsing without wasting one request per branch.
              if [ "$query" = "is:open" ] && [ $((''${#query} + ''${#term})) -gt 240 ]; then
                fetch_parent_batch "$repo" --head "$branch" || {
                  rm -rf "$work"
                  return 1
                }
                continue
              fi
              if [ "$query" != "is:open" ] && [ $((''${#query} + ''${#term})) -gt 240 ]; then
                fetch_parent_batch "$repo" --search "$query" || {
                  rm -rf "$work"
                  return 1
                }
                query="is:open"
              fi
              query="$query$term"
            done <"$bases"
            if [ "$query" != "is:open" ]; then
              fetch_parent_batch "$repo" --search "$query" || {
                rm -rf "$work"
                return 1
              }
            fi
          done <"$repos"

          if ! jq -s 'add // []' "$round" >"$parents"; then
            rm -rf "$work"
            return 1
          fi
          old_count=$(jq '.review | length' "$state") || {
            rm -rf "$work"
            return 1
          }
          if ! jq --slurpfile parents "$parents" '
            .review as $known
            | ($known | map(.url)) as $urls
            | .review += [
                ($parents[0] | unique_by(.url))[]
                | select(.url as $url | ($urls | index($url)) | not)
              ]
          ' "$state" >"$next_state"; then
            rm -rf "$work"
            return 1
          fi
          new_count=$(jq '.review | length' "$next_state") || {
            rm -rf "$work"
            return 1
          }
          mv "$next_state" "$state"
          [ "$new_count" -gt "$old_count" ] || break
          depth=$((depth + 1))
        done

        cp "$state" "$tmp" || {
          rm -rf "$work"
          return 1
        }
        rm -rf "$work"
      }

      # The $-names inside the quoted bodies below are GraphQL and jq
      # variables, not shell ones, and single quotes are exactly what keeps
      # bash out of them.
      # shellcheck disable=SC2016
      gh api graphql \
        -f openedQuery="is:pr author:@me created:>=$PR_SINCE" \
        -f reviewedQuery="is:pr reviewed-by:@me updated:>=$PR_SINCE" \
        -f query='
          query($openedQuery: String!, $reviewedQuery: String!) {
            review: search(query: "is:open is:pr review-requested:@me archived:false", type: ISSUE, first: 100) {
              nodes { ...pr }
            }
            mine: search(query: "is:open is:pr author:@me archived:false", type: ISSUE, first: 100) {
              nodes { ...pr }
            }
            # Deliberately unfiltered by state: a PR you opened and merged
            # before lunch still happened. `mine` cannot answer this — it is
            # is:open, and the whole point of a good day is that they close.
            # The date lives in a variable because the query is a single-quoted
            # nix/shell string, so nothing interpolates into it in place.
            openedToday: search(query: $openedQuery, type: ISSUE, first: 1) {
              issueCount
            }
            # GitHub has no "reviewed on" qualifier, so the search is only the
            # candidate net: submitting a review bumps that updatedAt past
            # local midnight, which makes updated:>= a superset of the answer.
            # viewerLatestReview.submittedAt is the actual cut — the same field
            # the queue above already trusts, and null while a review is still
            # an unsubmitted draft, which correctly scores as not reviewed yet.
            reviewedToday: search(query: $reviewedQuery, type: ISSUE, first: 100) {
              nodes {
                ... on PullRequest {
                  viewerLatestReview { submittedAt }
                }
              }
            }
          }
          fragment pr on PullRequest {
            repository { nameWithOwner }
            number
            title
            isDraft
            createdAt
            updatedAt
            url
            author { login }
            baseRefName
            headRefName
            additions
            deletions
            changedFiles
            # ponytail: the first 100 paths cover the useful directory hint;
            # paginate only if broad PRs make the model fall back to title scope.
            files(first: 100) { nodes { path } }
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
            created: .createdAt,
            updated: .updatedAt,
            url:    .url,
            draft:  .isDraft,
            decision: (.reviewDecision // ""),
            ci:     (.statusCheckRollup.state // ""),
            base:   .baseRefName,
            head:   .headRefName,
            additions: .additions,
            deletions: .deletions,
            changedFiles: .changedFiles,
            # A conventional-commit scope sent the model to the wrong area,
            # but the first two path components are worse: in this monorepo
            # they are always "js/apps" or "python/services" — the layout,
            # not the work. Dropping the layout words and the app name leaves
            # "features/patients" and "infra/audio-recorder", which is what
            # the shape prompt was actually calibrated against.
            # ponytail: a fixed word list, not a real path parser. Add words
            # here if a new language root shows up.
            files: (
              [
                .files.nodes[]?.path
                | split("/")
                | .[0:-1]
                | map(
                    select(
                      IN(
                        "js", "apps", "src", "python", "services",
                        "packages", "libs", "components",
                        "test", "tests", "__tests__"
                      ) | not
                    )
                  )
                | (if length > 1 then .[1:4] else .[0:1] end)
                | select(length > 0)
                | join("/")
              ]
              | unique
              | .[0:8]
            ),
            context: false
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
          # Lexical >=, which is a real time comparison only because both sides
          # are fixed-width UTC Z — what PR_SINCE goes to the trouble of
          # guaranteeing. Deliberately not fromdate: that builtin parses
          # %Y-%m-%dT%H:%M:%SZ and nothing else, so the offset form errors out.
          env.PR_SINCE as $since
          | {
            review: [ .data.review.nodes[] | select(awaiting_me) | norm ],
            mine:   [ .data.mine.nodes[]   | norm ],
            today: {
              opened: .data.openedToday.issueCount,
              reviewed: [
                .data.reviewedToday.nodes[]
                | .viewerLatestReview.submittedAt
                | select(. != null and . >= $since)
              ] | length
            }
          }' >"$tmp" 2>/dev/null

      # Only publish a well-formed, non-empty result. A network blip or an
      # expired token otherwise blanks the status bar, which reads exactly like
      # "you have no review requests" — the one lie this must never tell.
      if [ -s "$tmp" ] && jq -e 'has("review")' "$tmp" >/dev/null 2>&1; then
        # Parent lookups are supplemental. A partial GitHub failure must leave
        # the original queue intact rather than turning a status-bar outage into
        # an empty review list.
        resolve_parents || true
        mv "$tmp" "$CACHE"
        # Classification can take more than 300s. Publishing the queue first
        # keeps a slow model from turning a GitHub refresh into a frozen popup.
        ${tmux-pr-shape}/bin/tmux-pr-shape >/dev/null 2>&1 &
      fi
    '';
  };

  # A 1,400-line mechanical refactor took ten minutes; a 200-line datalayer
  # permission change took an hour. The queue needs the intent-to-diff gap,
  # not another size column.
  tmux-pr-shape = pkgs.writeShellApplication {
    name = "tmux-pr-shape";
    bashOptions = [ ];
    runtimeInputs = with pkgs; [
      coreutils
      jq
      opencode
    ];
    text = ''
            CACHE=${cache}
            SHAPES=${shapesFile}
            LOCK="$SHAPES.lock"

            [ -s "$CACHE" ] || exit 0
            mkdir -p "$(dirname "$SHAPES")" || exit 0

            # The model can outlive more than one 2-minute refresh. Without this
            # lock, each refresh would buy the same batch while the first run waits.
            if ! mkdir "$LOCK" 2>/dev/null; then
              exit 0
            fi

            work=$(mktemp -d) || {
              rmdir "$LOCK" 2>/dev/null || true
              exit 0
            }
            next=""
            cleanup() {
              rm -rf "$work"
              rm -f "$next"
              rmdir "$LOCK" 2>/dev/null || true
            }
            trap cleanup EXIT

            old="$work/old.json"
            selected="$work/selected.json"
            prompt="$work/prompt"
            response="$work/response"
            merged="$work/merged.json"

            if [ -f "$SHAPES" ] && jq -e 'type == "object"' "$SHAPES" >/dev/null 2>&1; then
              cp "$SHAPES" "$old" || exit 0
            else
              printf '{}' >"$old"
            fi

            # At ~$0.003 per full 40-PR pass on Haiku, updatedAt-keyed caching keeps
            # this cheap enough to forget. Without it, the 2-minute refresh would
            # re-run unchanged PRs continuously.
            #
            # ponytail: entries for closed PRs remain in state; a few hundred stale
            # records cost less than one model call, so prune only if the file matters.
            jq --slurpfile shapes "$old" '
              def plain: tostring | gsub("[\\t\\r\\n]+"; " ");
              def directories:
                .files // []
                | if length == 0 then "unknown" else join(", ") end;
              [ .review[]
                | select(.context != true)
                | select(($shapes[0][.url].updated // null) != .updated)
                | {
                    url: .url,
                    updated: .updated,
                    input: (
                      "#\(.number) @\(.author | plain) \(.title | plain)"
                      + "\n+\(.additions // 0)/-\(.deletions // 0) in \(.changedFiles // 0) files | \(directories)"
                      + "\nURL: \(.url)"
                    )
                  }
              ]
            ' "$CACHE" >"$selected" || exit 0

            jq -e 'length > 0' "$selected" >/dev/null 2>&1 || exit 0

            cat >"$prompt" <<'PROMPT'
      Classify GitHub PR review shape and review cost.

      Governing question: does the stated intent predict the code?
      - If the title tells you what the diff contains (flag flip, rename, bump, same change applied N times), it is confirmation and cheap NO MATTER THE SIZE. A 4000-line mechanical refactor can be a 10-minute review.
      - If the code could hold decisions the title does not imply (new behaviour, new boundaries, auth, data access, retention, PII, migrations), it must actually be read, and 200 lines can be an hour.

      SIZE IS NOT COST. Do not rank by lines changed.

      SHAPE, exactly one of:
        bump           dependency/lockfile churn
        flag           feature-flag flip, config, constant
        mechanical     rename/move/refactor with no behaviour change
        localized-fix  a bug fix inside one existing component
        known-feature  new feature in an area that already works this way
        new-surface    new subsystem, new integration, new public behaviour
        sensitive      touches auth, permissions, data access, retention, or PII
        unknown        too vague to infer

      sensitive means the diff itself changes an authorization, data-access, retention or PII rule — NOT merely that it touches a service that has such rules elsewhere. A UI change in an app that also contains auth code is not sensitive.

      COST, exactly one of: 2m 10m 30m 1h+

      Output one line per PR: <url>\t<shape>\t<cost>
      Output machine-readable TSV only, with no prose.
      Do not judge whether code is good. Do not recommend approving or rejecting anything. If too vague to infer, emit unknown and 30m.

      Each PR has its URL after its two summary lines. Use that exact URL in the output.

      PRs:
      PROMPT
            jq -r '.[].input' "$selected" >>"$prompt" || exit 0

            # This runs in an empty directory: the prompt supplies all the model may
            # see, and the throwaway session does not become noise in a PR repository.
            if ! opencode run --dir "$work" --title "tmux PR shape" -m "anthropic/claude-haiku-4-5" "$(<"$prompt")" \
              >"$response" 2>/dev/null; then
              exit 0
            fi

            # Models have wrapped TSV in prose and dropped three of forty PRs. Keep
            # the last good entry for every malformed or missing result; its updated
            # timestamp prevents a stale guess from reaching the popup.
            jq -Rrn --slurpfile old "$old" --slurpfile selected "$selected" '
              reduce inputs as $line (
                { shapes: $old[0], added: 0 };
                ($line | split("\t")) as $fields
                | if ($fields | length) == 3
                     and (["bump", "flag", "mechanical", "localized-fix", "known-feature", "new-surface", "sensitive", "unknown"] | index($fields[1]))
                     and (["2m", "10m", "30m", "1h+"] | index($fields[2]))
                  then ($selected[0] | map(select(.url == $fields[0])) | .[0]) as $pr
                    | if $pr == null
                      then .
                      else .shapes[$fields[0]] = {
                        shape: $fields[1],
                        cost: $fields[2],
                        updated: $pr.updated
                      } | .added += 1
                      end
                  else .
                  end
              )
            ' "$response" >"$merged" || exit 0

            jq -e '.added > 0' "$merged" >/dev/null 2>&1 || exit 0
            next=$(mktemp "$SHAPES.tmp.XXXXXX") || exit 0
            jq '.shapes' "$merged" >"$next" || exit 0
            mv "$next" "$SHAPES"
            next=""
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
      # Flexoki base-600. The queue is a thing to act on and the day's tallies
      # are a thing to notice, so they must not compete: same row, half the
      # contrast, no bold.
      MUTED="#6f6e69"

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
      # showing: `s` is a way to look at them, not a way to wake them. Context
      # parents make a tree readable, but were never assigned to you.
      n=$(jq -r --arg ign "$(cat "$IGNORE" 2>/dev/null)" '
        ${jqIgnore}
        .review | map(select(.context != true)) | live | length
      ' "$CACHE" 2>/dev/null) || exit 0

      case "''${n:-}" in "" | *[!0-9]*) exit 0 ;; esac

      # Today's tallies, written by the same refresh that filled the queue: no
      # second poll, no second cache, and they go stale on the same 2-minute
      # mtime check. Defaulted rather than required, because a cache written by
      # the previous build of this widget has no .today at all and one rebuild
      # should not blank the segment until the next refresh lands.
      read -r opened reviewed <<<"$(jq -r '
        [(.today.opened // 0), (.today.reviewed // 0)] | @tsv
      ' "$CACHE" 2>/dev/null)"

      case "''${opened:-}" in "" | *[!0-9]*) opened=0 ;; esac
      case "''${reviewed:-}" in "" | *[!0-9]*) reviewed=0 ;; esac

      # Silent at zero, like the disk widget: an empty queue is not news, and a
      # segment that is always on screen is a segment you stop seeing. Snoozing
      # the last PR therefore clears the slot entirely, which is the point of
      # snoozing it.
      #
      # All-or-nothing, and the three numbers never hide individually: without
      # a glyph on each one, position is the only thing saying which is which,
      # and a lone "58 6" cannot be read as queue-plus-reviewed rather than
      # queue-plus-opened. Hiding a zero would silently shift the survivors one
      # slot left and quietly change what the row means. So the zeros stay as
      # placeholders, and only an entirely empty day clears the segment.
      if [ "$n" -eq 0 ] && [ "$opened" -eq 0 ] && [ "$reviewed" -eq 0 ]; then
        exit 0
      fi

      # One leading and one trailing space for the whole block, single spaces
      # inside it. Every widget here pads itself on both sides, so the gap
      # between two widgets is always two — padding each number that way made
      # them read as three unrelated segments, indistinguishable from todoist
      # and cpu sitting beside them.
      #
      # Slash-joined rather than space-joined, which costs the same width and
      # buys the grouping: on a row where every other widget is also an icon
      # followed by a number, three space-separated numbers read as three
      # widgets. 58/1/6 reads as one compound value, which is what it is.
      #
      # Only the queue is black and bold: it is the number you act on, and the
      # icon marks the block as PRs so three bare numbers are not stranded next
      # to the todoist count. The tallies stay muted, a thing to notice — the
      # style switches at the first slash so the separators travel with them.
      echo "#[fg=''${FG},bg=''${BG},bold] ''${GH} ''${n}#[fg=''${MUTED},bg=''${BG},nobold]/''${opened}/''${reviewed}''${RESET} "
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
      SHAPES=${shapesFile}
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
        local shapes
        # A partial write must look exactly like no classifier: the popup is
        # useful before its first model result, and never gets to depend on it.
        shapes=$(jq -c 'if type == "object" then . else {} end' "$SHAPES" 2>/dev/null) || shapes='{}'

        jq -r --arg ign "$(cat "$IGNORE" 2>/dev/null)" --argjson shapes "$shapes" --arg view "$1" --arg show "$2" '
          ${jqIgnore}
          ${jqTree}

            def dim: "\u001b[2m"  + . + "\u001b[0m";
            def red: "\u001b[31m" + . + "\u001b[0m";
            def grn: "\u001b[32m" + . + "\u001b[0m";
            def yel: "\u001b[33m" + . + "\u001b[0m";

            def shape_badge:
              ($shapes[.url] // null) as $shape
              | if .context == true or $shape == null or $shape.updated != .updated
                then ""
                elif $shape.shape == "sensitive"
                  then ($shape.cost + " " + $shape.shape + "  " | red)
                else ($shape.cost + " " + $shape.shape + "  " | dim)
                end;

            # #5191 was created 59d ago and requested review 53d ago, but an
            # active author left updatedAt reading 8d. That hid up to 45d of
            # waiting, which is the opposite of a queue tiebreaker.
            def review_cost:
              ($shapes[.url] // null) as $shape
              | if .context == true or $shape == null or $shape.updated != .updated
                then "30m"
                else $shape.cost
                end;
            def cost_minutes:
              review_cost
              | if   . == "2m"  then 2
                elif . == "10m" then 10
                elif . == "30m" then 30
                else                  60
                end;
            def cost_band:
              if   . <= 2  then 0
              elif . <= 10 then 1
              elif . <= 30 then 2
              else              3
              end;
            def review_tree_forest($nodes):
              [ tree_roots($nodes)[] as $root
                | [ tree($nodes; $root; 0) ] as $rows
                | ($rows | map(cost_minutes) | add) as $total
                | {
                    band: ($total | cost_band),
                    created: ($rows | map(.created) | min),
                    members: ($rows | length),
                    rows: $rows,
                    treeRoot: ($root | ref)
                  }
              ]
              | sort_by([.band, .created])
              | .[]
              | .members as $members
              | .treeRoot as $treeRoot
              | .rows[]
              | . + { members: $members, treeRoot: $treeRoot };

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
          | (if $show == "1" then . else live end) as $rows
          | if $view == "review"
            then review_tree_forest($rows)
            else ($rows | sort_by(.updated) | reverse | .[] | . + { depth: 0, members: 1 })
            end
          | [ .url,
              ( ( (if $view == "review" and .members > 1
                    then (if .depth == 0
                          then ("[" + (.members | tostring) + " PRs] " | dim)
                          else (("  " * .depth) + "↳ " | dim)
                          end)
                    else ""
                    end)
                  + ((.repo | split("/") | last) + "#" + (.number | tostring) | dim)
                  + "  " + (if .draft then ("draft " | dim) else "" end)
                  + (if .context then ("context " | dim) else "" end)
                  + shape_badge
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
          [ (.review | map(select(.context != true)) | live | length),
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
        printf 'enter open · t tree · x snooze · s show · u clear · / search · tab view · r refresh\n'
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
          # The row already carries the url, so opening it needs nothing from
          # the GitHub API — but routing it through `gh` did. During a GitHub
          # 503 every enter press became a silent no-op, because the failure
          # is deliberately swallowed so a dead opener cannot kill the popup.
          # The desktop opener has no network in its path; gh stays only as
          # the fallback for hosts without one.
          open "$2" >/dev/null 2>&1 || gh pr view --web "$2" >/dev/null 2>&1 || true
          exit 0
          ;;
        --open-tree)
          [ -n "''${2:-}" ] || exit 0
          urls=$(jq -r --arg url "$2" '
            ${jqTree}
            .review as $rows
            | [ tree_forest($rows) ] as $forest
            | ($forest[] | select(.url == $url) | .treeRoot) as $tree_root
            | $forest[] | select(.treeRoot == $tree_root) | .url
          ' "$CACHE" 2>/dev/null) || urls=""
          # Each opener returns only after handing the tab to the browser, so
          # this preserves the root→leaf reading order in tabs. Same reason as
          # --open for preferring the desktop opener: a whole tree silently
          # failing to open is the worst version of that bug.
          while IFS= read -r url; do
            [ -n "$url" ] || continue
            open "$url" >/dev/null 2>&1 || gh pr view --web "$url" >/dev/null 2>&1 || true
          done <<<"$urls"
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
      # shellcheck disable=SC2016  # {1} is fzf's placeholder, not a shell var
      b_tree='execute-silent('"$self"' --open-tree {1})'
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
      b_search='unbind(change)+unbind(t)+unbind(x)+unbind(s)+unbind(u)+unbind(r)+unbind(/)+clear-query+change-prompt(/ )+enable-search'
      # Back to menu mode: reload repopulates the full list, since disable-search
      # on its own freezes whatever subset the last query left behind.
      b_esc_back='clear-query+disable-search+change-prompt(❯ )+rebind(change)+rebind(t)+rebind(x)+rebind(s)+rebind(u)+rebind(r)+rebind(/)+'"$redraw"
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
        --bind "t:$b_tree" \
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
