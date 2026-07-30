# Stack-aware session picker — an fzf popup that replaces the choose-tree
# session picker. It opens as a menu (fzf --disabled: keystrokes are shortcuts,
# not a filter) so it feels close to a native menu, and "/" switches to live
# fuzzy search. Layout is a tree: roots alphabetical (same as choose-tree
# -O name), worktree sessions nested under their root with ├─/└─ connectors,
# and (once a stack source is wired up) stacked worktrees indented by depth.
# Every line is a selectable session — no separator or header lines — so j/k
# never land on dead rows.
#
# Menu mode: j/k navigate, Enter switches, x kills (with y/n confirm), "/"
# enters search. Search mode: type to filter live, Enter switches, Esc returns
# to menu mode. The original native choose-tree picker moves to prefix+S.
{ pkgs, choose-tree-picker }:
let
  # Computes per-session metadata into tmux session options, all read by the
  # picker from cache (never on its critical path):
  #   @wt-label  branch label (root sessions on a non-default branch only)
  #   @wt-sort   topological stack chain (US-delimited) — currently always
  #              empty (no stack source wired up); the picker renders a flat
  #              per-root tree until one repopulates it.
  #   @wt-oc     opencode attention glyph (pre-colored): ◍ busy · ● done ·
  #              ⏸ permission · ? question · ‼ error. Empty when idle/none.
  #              Source: tmux-opencode-manager (soft dep; skipped if absent).
  #   @wt-pr     PR glyph (pre-colored): #N open · "draft" · ⇧#N ready-to-merge
  #              (approved + CI green + no conflicts) · ✔#N merged. Closed-
  #              unmerged PRs get no glyph (treated like no PR).
  #   @wt-ci     CI/mergeability glyph (pre-colored): ✓ pass · ✗ fail ·
  #              • pending · ⚠ merge conflict (overrides CI). Empty for merged
  #              and ready-to-merge PRs (green is implied).
  # PR/CI come from one bounded `gh pr list --head` call per session branch —
  # newest open PR wins, else newest merged — each cached to its own tmpfile
  # with a 60s TTL so spamming the picker can't hammer the GitHub API. tmux-wt-pick reads every option
  # verbatim, so wiring a future stack source back into @wt-sort needs no
  # picker changes.
  #
  # Runs async (run-shell -b on picker open + session-created hook), never on
  # the picker's critical path: the picker reads only cached options, so each
  # open shows the previous refresh's data and triggers the next one.
  tmux-wt-refresh = pkgs.writeShellApplication {
    name = "tmux-wt-refresh";
    runtimeInputs = with pkgs; [
      tmux
      git
      gh
      jq
      coreutils
    ];
    text = ''
      TAB=$'\t'
      US=$'\x1f'

      # MAG is a 256-color purple: the 16-color magenta (35) reads as red in
      # some terminal themes, so pin it explicitly.
      DIM=$'\033[2m'
      RST=$'\033[0m'
      RED=$'\033[31m'
      GRN=$'\033[32m'
      YEL=$'\033[33m'
      MAG=$'\033[38;5;135m'

      # ── opencode attention (session name → pre-colored glyph) ────────────
      # Soft dep: tmux-opencode-manager (opencode-manager module). Absent →
      # opencode glyphs are simply skipped. A pending notification means "needs
      # YOU" and overrides a busy spinner; highest-severity event wins.
      declare -A OC_GLYPH OC_RANK
      if command -v tmux-opencode-manager >/dev/null 2>&1; then
        while IFS= read -r s; do
          [[ -z "$s" ]] && continue
          OC_GLYPH["$s"]="''${DIM}◍''${RST}"
          OC_RANK["$s"]=0
        done < <(tmux-opencode-manager sessions 2>/dev/null \
          | jq -r '.[] | select(.status=="generating") | .session' 2>/dev/null || true)

        while IFS="$TAB" read -r s ev; do
          [[ -z "$s" ]] && continue
          case "$ev" in
            error) g="''${RED}‼''${RST}"; rank=4 ;;
            question) g="''${YEL}?''${RST}"; rank=3 ;;
            permission) g="''${YEL}⏸''${RST}"; rank=2 ;;
            *) g="''${GRN}●''${RST}"; rank=1 ;; # complete / awaiting
          esac
          if (( rank > ''${OC_RANK["$s"]:-0} )); then
            OC_GLYPH["$s"]="$g"
            OC_RANK["$s"]=$rank
          fi
        done < <(tmux-opencode-manager notify list 2>/dev/null \
          | jq -r '.[] | "\(.session)\t\(.event)"' 2>/dev/null || true)
      fi

      # ── PR + CI per session branch (one bounded gh call, 60s TTL cache) ──
      # Asks for exactly the branch in front of you, never the whole repo. Two
      # earlier repo-wide designs both failed on a busy monorepo, and both
      # failed the same way — silently, by returning fewer PRs than exist:
      #   --state all + rollup → "unexpected end of JSON input"
      #   --state open + rollup → HTTP 504 past ~100 PRs in a page (224 open)
      #   --author @me         → routes through the SEARCH api (verified via
      #     GH_DEBUG=api: query PullRequestSearch), which is eventually
      #     consistent and answers 200-with-zero-rows while its index lags. An
      #     empty success is indistinguishable from "no PR", so every glyph
      #     silently vanished until the next refresh.
      # --head instead hits the repo's pullRequests(headRefName:) connection
      # directly: no search index, no 300-PR page, no rollup fan-out. It is
      # deterministic, ~0.9s, and cannot degrade into a plausible-looking lie.
      # It also fixes two ceilings of the old design for free — a PR opened by
      # someone else on your branch now shows, and so does one merged further
      # back than the old 200-PR merged window.
      #
      # ponytail: one gh call per session branch (~8 here) instead of two per
      # repo. Sequential, but it runs detached via `run-shell -b` and is capped
      # by the TTL below; parallelize with & + wait if the session count grows.
      pr_row() {
        local path="$1" cdir="$2" branch="$3" cache now age row
        [[ -z "$cdir" || -z "$branch" ]] && return 0
        cache="''${TMPDIR:-/tmp}/wt-pr-$(printf '%s%s%s' "$cdir" "$US" "$branch" | cksum | cut -d' ' -f1)"
        now=$(date +%s)
        age=999
        [[ -f "$cache" ]] && age=$(( now - $(stat -c %Y "$cache" 2>/dev/null || echo 0) ))
        # ponytail: 60s TTL cap so picker spam can't hammer the gh API; lower
        # it if PR/CI ever feels stale. CI classification is a heuristic over
        # the mixed CheckRun/StatusContext rollup — fail wins, then pending.
        if (( age > 60 )); then
          # Newest open PR wins, else newest merged; closed-unmerged yields
          # nothing (treated as no PR). Only overwrite the cache when gh
          # actually succeeded — a failed lookup keeps the last known glyph
          # rather than reading as "this branch has no PR".
          # SC2016: $p/$o/$m/$x/$c/$ci are jq syntax, not shell.
          # shellcheck disable=SC2016
          if row=$( cd "$path" && gh pr list --head "$branch" --state all --limit 10 \
              --json number,state,isDraft,statusCheckRollup,reviewDecision,mergeable \
              --jq '[ .[] | select(.state=="OPEN" or .state=="MERGED") ] as $p
                | ( [ $p[] | select(.state=="OPEN")   ] | sort_by(.number) | last ) as $o
                | ( [ $p[] | select(.state=="MERGED") ] | sort_by(.number) | last ) as $m
                | ( $o // $m ) as $x
                | if $x == null then empty else
                    ( [ $x.statusCheckRollup[]? ] as $c |
                      if ($c|length)==0 then "none"
                      elif ([$c[] | (.conclusion // .state // "")] | any(IN("FAILURE","ERROR","CANCELLED","TIMED_OUT","FAILED","STARTUP_FAILURE"))) then "fail"
                      elif ([$c[] | (.status // "")] | any(IN("IN_PROGRESS","QUEUED","PENDING","WAITING","REQUESTED"))) or ([$c[] | (.state // "")] | any(IN("PENDING","EXPECTED"))) then "pending"
                      else "pass" end ) as $ci
                    | [ ($x.isDraft|tostring), ($x.number|tostring), $x.state,
                        (if $x.state=="MERGED" then "none" else $ci end),
                        (if $x.state=="MERGED" then "no"
                         elif $x.mergeable=="CONFLICTING" then "conflict"
                         elif ($x.isDraft|not) and ($x.reviewDecision=="APPROVED") and ($ci=="pass") then "ready"
                         else "no" end) ]
                    | join("|")
                  end' 2>/dev/null ); then
            printf '%s\n' "$row" >"$cache" 2>/dev/null || true
          fi
        fi
        cat "$cache" 2>/dev/null || true
        return 0
      }

      tmux list-sessions -F "#{session_name}''${TAB}#{session_path}" 2>/dev/null |
        while IFS="$TAB" read -r name path; do
          [[ "$name" == "pocket" ]] && continue

          ocg="''${OC_GLYPH[$name]:-}"
          cdir=$(git -C "$path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
          branch=$(git -C "$path" branch --show-current 2>/dev/null || true)

          label=""
          prg=""
          cig=""
          if [[ -n "$branch" ]]; then
            # Hide the default branch on roots — only deviations are interesting.
            if [[ "$name" != */* ]]; then
              default=$(git -C "$path" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
              default="''${default#origin/}"
              [[ "$branch" != "$default" ]] && label="$branch"
            fi
            if [[ -n "$cdir" ]]; then
              data=$(pr_row "$path" "$cdir" "$branch")
              if [[ -n "$data" ]]; then
                IFS='|' read -r draft num state ci flag <<<"$data"
                case "$state" in
                  MERGED)
                    # Merged → work landed (safe to reap); CI is irrelevant.
                    prg="''${MAG}✔''${RST}''${DIM}#''${num}''${RST}"
                    ;;
                  OPEN)
                    if [[ "$draft" == "true" ]]; then
                      prg="''${DIM}draft''${RST}"
                    elif [[ "$flag" == "conflict" ]]; then
                      # Merge conflicts block everything → ⚠ overrides CI status.
                      prg="''${DIM}#''${num}''${RST}"
                      cig="''${RED}⚠''${RST}"
                    elif [[ "$flag" == "ready" ]]; then
                      # Approved + CI green + no conflicts → merge it. CI glyph
                      # suppressed (green is implied by the ⇧).
                      prg="''${GRN}⇧#''${num}''${RST}"
                    else
                      prg="''${DIM}#''${num}''${RST}"
                      case "$ci" in
                        pass) cig="''${GRN}✓''${RST}" ;;
                        fail) cig="''${RED}✗''${RST}" ;;
                        pending) cig="''${YEL}•''${RST}" ;;
                      esac
                    fi
                    ;;
                  *) ;; # CLOSED (unmerged) → no glyphs, treat like no PR
                esac
              fi
            fi
          fi

          # set-option rejects the "=" exact-match prefix (target-pane parser);
          # bare names resolve exact-first, so this is safe.
          tmux set-option -t "$name" @wt-label "$label" 2>/dev/null || true
          tmux set-option -t "$name" @wt-sort "" 2>/dev/null || true
          tmux set-option -t "$name" @wt-oc "$ocg" 2>/dev/null || true
          tmux set-option -t "$name" @wt-pr "$prg" 2>/dev/null || true
          tmux set-option -t "$name" @wt-ci "$cig" 2>/dev/null || true
        done
    '';
  };

  tmux-wt-pick = pkgs.writeShellApplication {
    name = "tmux-wt-pick";
    runtimeInputs = with pkgs; [
      tmux
      fzf
      gh
      coreutils
      gnugrep
    ];
    text = ''
      # Field separator for tmux -F output and internal rows. Must be
      # non-whitespace: IFS treats tab/space as whitespace-class and COLLAPSES
      # adjacent ones, which would eat an empty @wt-label sitting before a
      # populated @wt-sort chain. RS (0x1e) is non-whitespace so empty fields
      # survive. US (0x1f) is reserved for the chain's own delimiter.
      RS=$'\x1e'
      US=$'\x1f'

      DIM=$'\033[2m'
      RST=$'\033[0m'
      CUR=$'\033[32m'

      # build_list prints one line per session: "<target>\t<display>". target is
      # the session name (used by the binds via {1}); display is the decorated,
      # tree-indented label shown by fzf (--with-nth=2).
      build_list() {
        current=$(tmux display-message -p '#S' 2>/dev/null || true)
        # Status cluster (opencode/PR/CI glyphs) keyed by session name, joined
        # from the three pre-colored @wt-* options. Looked up at print time so
        # the glyphs don't have to thread through the sort below.
        declare -A STATUS
        rows=()
        while IFS="$RS" read -r name label chain oc pr ci; do
          [[ -z "$name" || "$name" == "pocket" ]] && continue
          cluster=""
          for g in "$oc" "$pr" "$ci"; do [[ -n "$g" ]] && cluster+="''${cluster:+ }$g"; done
          STATUS["$name"]="$cluster"
          root="''${name%%/*}"
          if [[ "$name" == "$root" ]]; then
            cls=0 key="$name"
          elif [[ -z "$chain" ]]; then
            cls=1 key="$name"
          else
            cls=2 key="$chain"
          fi
          rows+=("''${root}''${RS}''${cls}''${RS}''${key}''${RS}''${name}''${RS}''${label}''${RS}''${chain}")
        done < <(tmux list-sessions -F "#{session_name}''${RS}#{@wt-label}''${RS}#{@wt-sort}''${RS}#{@wt-oc}''${RS}#{@wt-pr}''${RS}#{@wt-ci}" 2>/dev/null)

        ((''${#rows[@]} == 0)) && return 0

        # Chains sort parents before children (prefix property), keeping each
        # stack contiguous and topologically ordered.
        mapfile -t sorted < <(printf '%s\n' "''${rows[@]}" | LC_ALL=C sort -t "$RS" -k1,1 -k2,2n -k3,3)

        # Pass 1: which roots have a bare root session, and worktree-child counts
        # (to draw └─ for the last child).
        declare -A HAS_ROOT WT_COUNT WT_SEEN
        for row in "''${sorted[@]}"; do
          IFS="$RS" read -r root cls _ _ _ _ <<<"$row"
          if ((cls == 0)); then
            HAS_ROOT["$root"]=1
          else
            WT_COUNT["$root"]=$((''${WT_COUNT["$root"]:-0} + 1))
          fi
        done

        # Pass 2: one line per session, grouped into a tree under each root.
        for row in "''${sorted[@]}"; do
          IFS="$RS" read -r root cls _ name label chain <<<"$row"

          mark="  "
          [[ "$name" == "$current" ]] && mark="''${CUR}●''${RST} "

          if ((cls == 0)); then
            body="$name"
          elif [[ -n "''${HAS_ROOT[$root]:-}" ]]; then
            WT_SEEN["$root"]=$((''${WT_SEEN["$root"]:-0} + 1))
            if ((WT_SEEN[$root] == WT_COUNT[$root])); then conn="└─"; else conn="├─"; fi
            extra=""
            if [[ -n "$chain" ]]; then
              nous="''${chain//"$US"/}"
              depth=$((''${#chain} - ''${#nous}))
              for ((i = 1; i < depth; i++)); do extra+="  "; done
            fi
            body="  ''${DIM}''${conn}''${RST} ''${extra}''${name#*/}"
          else
            # Worktree whose root session is not present: full name, no tree.
            body="$name"
          fi

          [[ -n "$label" ]] && body="''${body}  ''${DIM}''${label}''${RST}"
          sc="''${STATUS[$name]:-}"
          [[ -n "$sc" ]] && body="''${body}  $sc"
          printf '%s\t%s%s\n' "$name" "$mark" "$body"
        done
      }

      if [[ "''${1:-}" == "--list" ]]; then
        # Cache the last non-empty render. tmux list-sessions can momentarily
        # return empty under server contention — the background refresh fires a
        # burst of set-option calls as the popup opens. You are always in ≥1
        # session when the picker is open, so a blank build is never correct;
        # fall back to the last good list instead of showing nothing. Covers
        # the in-fzf reload() actions too, since they call --list.
        pick_cache="''${TMPDIR:-/tmp}/wt-pick-last.list"
        out=$(build_list || true)
        if [[ -n "$out" ]]; then
          printf '%s\n' "$out" >"$pick_cache" 2>/dev/null || true
          printf '%s\n' "$out"
        else
          cat "$pick_cache" 2>/dev/null || true
        fi
        exit 0
      fi

      # Open the highlighted session's branch PR in the browser (bound to `o`).
      # gh resolves the PR from the branch in the session's dir; no PR → no-op.
      if [[ "''${1:-}" == "--open-pr" ]]; then
        # Bare name (not =name): display-message rejects the "=" exact-match
        # prefix, same as set-option; bare resolves exact-first, so it's safe.
        p=$(tmux display-message -p -t "''${2:-}" '#{session_path}' 2>/dev/null || true)
        [[ -n "$p" ]] && cd "$p" && gh pr view --web >/dev/null 2>&1 || true
        exit 0
      fi

      self="$0"
      list=$("$self" --list)
      [[ -z "$list" ]] && exit 0

      # Start positioned on the current session (needs --sync, see below).
      current=$(tmux display-message -p '#S' 2>/dev/null || true)
      pos=$(printf '%s\n' "$list" | grep -n -m1 -F "$current"$'\t' | cut -d: -f1 || true)
      : "''${pos:=1}"

      # Menu mode by default (--disabled): printable keys are shortcuts, not a
      # filter. "/" switches to live search (unbinds the shortcut letters so they
      # type again) and changes the prompt to "/ "; Esc returns to menu mode
      # (detected via $FZF_PROMPT). fzf field 1 = target session ({1}, plain),
      # field 2 = display. transform~...~ uses ~ as delimiter because the action
      # bodies contain ()/[] that the default (...) parser would choke on.
      # shellcheck disable=SC2016  # $FZF_PROMPT / $a / {N} are for fzf+sh, not bash
      b_enter='transform~[ -n {1} ] && echo "become(tmux switch-client -t ={1})" || echo ignore~'
      # shellcheck disable=SC2016
      b_kill='execute([ -n {1} ] && { printf "kill %s? [y/N] " {1}; read -r a </dev/tty; [ "$a" = y ] && tmux kill-session -t ={1}; })+reload('"$self"' --list)'
      # shellcheck disable=SC2016
      b_pr='execute('"$self"' --open-pr {1})'
      b_search='unbind(x)+unbind(o)+unbind(j)+unbind(k)+unbind(q)+unbind(/)+clear-query+change-prompt(/ )+enable-search'
      # Returning to menu mode: reload($self --list) repopulates the full list
      # (disable-search alone freezes the last filtered subset).
      b_esc_back='clear-query+disable-search+change-prompt(❯ )+rebind(x)+rebind(o)+rebind(j)+rebind(k)+rebind(q)+rebind(/)+reload('"$self"' --list)'
      # shellcheck disable=SC2016
      b_esc='transform~[ "$FZF_PROMPT" = "/ " ] && echo "'"$b_esc_back"'" || echo abort~'

      # --sync: load all input before the start event fires, so start:pos($pos)
      # reliably lands on the current session (without it, pos runs before the
      # piped list is loaded and is ignored). The list is already in memory, so
      # EOF is immediate — no added latency.
      printf '%s\n' "$list" | fzf \
        --ansi --no-sort --layout=reverse --cycle \
        --delimiter='\t' --with-nth=2 \
        --disabled --sync \
        --prompt='❯ ' \
        --info=inline-right \
        --pointer='▶' \
        --gutter=' ' \
        --color='pointer:green,prompt:green,info:dim,header:dim' \
        --header='enter switch · x kill · o PR · / search' \
        --bind "start:pos($pos)" \
        --bind "enter:$b_enter" \
        --bind 'j:down' \
        --bind 'k:up' \
        --bind "x:$b_kill" \
        --bind "o:$b_pr" \
        --bind 'q:abort' \
        --bind "/:$b_search" \
        --bind "esc:$b_esc"
    '';
  };
in
{
  home = {
    home.packages = [
      tmux-wt-refresh
      tmux-wt-pick
    ];
    programs.tmux.extraConfig = ''
      # Stack-aware session picker on prefix+s. The refresh runs in the
      # background while the popup opens with the previous data (self-healing
      # staleness — fresh by the next open).
      bind-key s run-shell -b '${tmux-wt-refresh}/bin/tmux-wt-refresh >/dev/null 2>&1' \; display-popup -E -w 60% -h 60% '${tmux-wt-pick}/bin/tmux-wt-pick'

      # Original native choose-tree picker (same rules) as fallback.
      bind-key S ${choose-tree-picker}

      # Prime metadata when sessions appear. Indexed hook so other modules'
      # global hooks (e.g. opencode-manager) are not clobbered.
      set-hook -g 'session-created[20]' 'run-shell -b "${tmux-wt-refresh}/bin/tmux-wt-refresh"'
    '';
  };
}
