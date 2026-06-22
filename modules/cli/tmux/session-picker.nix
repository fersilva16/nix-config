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
  # Computes per-session git metadata into tmux session options:
  #   @wt-label  status label (empty for non-git sessions)
  #   @wt-sort   topological stack chain (US-delimited) — currently always
  #              empty. The av stack source was removed, so the picker renders a
  #              flat per-root tree until a new stack source repopulates this
  #              option. tmux-wt-pick still understands @wt-sort, so wiring a
  #              future stack source back in needs no picker changes.
  # Labels rely on session names for identity: worktree sessions (name contains
  # "/") show no label; root sessions show their branch only when it differs
  # from the repo's default (origin/HEAD).
  # Runs async (run-shell -b on picker open + session-created hook), never on
  # the picker's critical path: the picker reads only cached options, so each
  # open shows the previous refresh's data and triggers the next one.
  tmux-wt-refresh = pkgs.writeShellApplication {
    name = "tmux-wt-refresh";
    runtimeInputs = with pkgs; [
      tmux
      git
    ];
    text = ''
      TAB=$'\t'
      tmux list-sessions -F "#{session_name}''${TAB}#{session_path}" 2>/dev/null |
        while IFS=$'\t' read -r name path; do
          [[ "$name" == "pocket" ]] && continue

          branch=$(git -C "$path" branch --show-current 2>/dev/null || true)
          if [[ -z "$branch" ]]; then
            # set-option rejects the "=" exact-match prefix (target-pane
            # parser); bare names resolve exact-first, so this is safe.
            tmux set-option -t "$name" @wt-label "" 2>/dev/null || true
            tmux set-option -t "$name" @wt-sort "" 2>/dev/null || true
            continue
          fi

          label=""
          if [[ "$name" != */* ]]; then
            # Hide the default branch — only deviations are interesting.
            default=$(git -C "$path" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
            default="''${default#origin/}"
            if [[ "$branch" != "$default" ]]; then label="$branch"; fi
          fi
          tmux set-option -t "$name" @wt-label "$label" 2>/dev/null || true
          tmux set-option -t "$name" @wt-sort "" 2>/dev/null || true
        done
    '';
  };

  tmux-wt-pick = pkgs.writeShellApplication {
    name = "tmux-wt-pick";
    runtimeInputs = with pkgs; [
      tmux
      fzf
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
        rows=()
        while IFS="$RS" read -r name label chain; do
          [[ -z "$name" || "$name" == "pocket" ]] && continue
          root="''${name%%/*}"
          if [[ "$name" == "$root" ]]; then
            cls=0 key="$name"
          elif [[ -z "$chain" ]]; then
            cls=1 key="$name"
          else
            cls=2 key="$chain"
          fi
          rows+=("''${root}''${RS}''${cls}''${RS}''${key}''${RS}''${name}''${RS}''${label}''${RS}''${chain}")
        done < <(tmux list-sessions -F "#{session_name}''${RS}#{@wt-label}''${RS}#{@wt-sort}" 2>/dev/null)

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
          printf '%s\t%s%s\n' "$name" "$mark" "$body"
        done
      }

      if [[ "''${1:-}" == "--list" ]]; then
        build_list
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
      b_search='unbind(x)+unbind(j)+unbind(k)+unbind(q)+unbind(/)+clear-query+change-prompt(/ )+enable-search'
      # Returning to menu mode: reload($self --list) repopulates the full list
      # (disable-search alone freezes the last filtered subset).
      b_esc_back='clear-query+disable-search+change-prompt(❯ )+rebind(x)+rebind(j)+rebind(k)+rebind(q)+rebind(/)+reload('"$self"' --list)'
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
        --header='enter switch · x kill · / search' \
        --bind "start:pos($pos)" \
        --bind "enter:$b_enter" \
        --bind 'j:down' \
        --bind 'k:up' \
        --bind "x:$b_kill" \
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
