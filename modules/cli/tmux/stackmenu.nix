# Stack-aware session picker — a native display-menu replacement for the
# choose-tree session picker. Native menus render in-process (no popup shell,
# no fzf), so opening is as fast as choose-tree, while we fully control item
# order: roots alphabetical (same as choose-tree -O name), worktree sessions
# grouped under their root, and (once a stack source is wired up) stacked
# worktrees in topological PR order.
# j/k navigate (tmux's menu.c maps them to up/down), 1-9 jump, Enter switches,
# q/Esc cancels, x opens kill mode (choose a session, y/n confirm, repeat).
# The original choose-tree picker moves to prefix+S.
{ pkgs, choose-tree-picker }:
let
  # Computes per-session git metadata into tmux session options:
  #   @wt-label  status label (empty for non-git sessions)
  #   @wt-sort   topological stack chain (US-delimited) — currently always
  #              empty. The av stack source was removed, so the menu renders a
  #              flat per-root session list until a new stack source repopulates
  #              this option. tmux-wt-menu still understands @wt-sort, so wiring
  #              a future stack source back in needs no menu changes.
  # Labels rely on session names for identity: worktree sessions (name contains
  # "/") show no label; root sessions show their branch only when it differs
  # from the repo's default (origin/HEAD).
  # Runs async (run-shell -b on picker open + session-created hook), never on
  # the picker's critical path: the menu reads only cached options, so each open
  # shows the previous refresh's data and triggers the next one.
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

  tmux-wt-menu = pkgs.writeShellApplication {
    name = "tmux-wt-menu";
    runtimeInputs = with pkgs; [
      tmux
      coreutils
    ];
    text = ''
      # Modes: default = choosing a session switches to it; "x" opens kill
      # mode (--kill), where choosing a session kills it after a y/n confirm
      # and the kill-mode menu reopens for further cleanup. "x" toggles back.
      MODE="''${1:-}"

      TAB=$'\t'
      US=$'\x1f'
      current=$(tmux display-message -p '#{session_name}' 2>/dev/null || true)

      # Collect rows: root, class (0=root session, 1=plain worktree,
      # 2=stacked), sort key (name or topo chain), name, label, chain.
      rows=()
      while IFS=$'\t' read -r name label chain; do
        [[ -z "$name" || "$name" == "pocket" ]] && continue
        root="''${name%%/*}"
        if [[ "$name" == "$root" ]]; then
          cls=0 key="$name"
        elif [[ -z "$chain" ]]; then
          cls=1 key="$name"
        else
          cls=2 key="$chain"
        fi
        rows+=("$root$TAB$cls$TAB$key$TAB$name$TAB$label$TAB$chain")
      done < <(tmux list-sessions -F "#{session_name}$TAB#{@wt-label}$TAB#{@wt-sort}" 2>/dev/null)

      if ((''${#rows[@]} == 0)); then exit 0; fi

      # Chains sort parents before children (prefix property), keeping each
      # stack contiguous and topologically ordered.
      mapfile -t sorted < <(printf '%s\n' "''${rows[@]}" | LC_ALL=C sort -t "$TAB" -k1,1 -k2,2n -k3,3)

      # Pass 1: name column width + per-stack session counts (headers need >= 2).
      declare -A STACK_N
      maxlen=0
      for row in "''${sorted[@]}"; do
        IFS=$'\t' read -r root _ _ name _ chain <<<"$row"
        if ((''${#name} > maxlen)); then maxlen=''${#name}; fi
        if [[ -n "$chain" ]]; then
          bottom="''${chain%%"$US"*}"
          STACK_N["$root|$bottom"]=$((''${STACK_N["$root|$bottom"]:-0} + 1))
        fi
      done

      # Pass 2: build menu items.
      args=()
      idx=0   # item index in the menu (separators/headers count)
      start=0 # -C starting choice: keep the current session selected
      si=0
      shortcuts="123456789"
      prev_root=""
      prev_bottom=""
      for row in "''${sorted[@]}"; do
        IFS=$'\t' read -r root _ _ name label chain <<<"$row"

        if [[ -n "$prev_root" && "$root" != "$prev_root" ]]; then
          args+=("") # separator between root groups (single empty arg)
          idx=$((idx + 1))
          prev_bottom=""
        fi
        prev_root="$root"

        indent=""
        if [[ -n "$chain" ]]; then
          bottom="''${chain%%"$US"*}"
          if [[ "$bottom" != "$prev_bottom" ]] && ((''${STACK_N["$root|$bottom"]:-0} >= 2)); then
            # Header named after the stack's first present session (worktree
            # name), not the branch — branch names are Linear-generated noise.
            # Leading "-" = disabled item (dimmed, skipped by j/k); unlike
            # separators it needs the full name/key/command triple.
            args+=("-── stack: ''${name#*/} ──" "" "")
            idx=$((idx + 1))
          fi
          prev_bottom="$bottom"
          nous="''${chain//"$US"/}"
          depth=$((''${#chain} - ''${#nous}))
          for ((i = 0; i < depth; i++)); do indent+="· "; done
          if ((depth > 0)); then indent+="↳ "; fi
        else
          prev_bottom=""
        fi

        mark=" "
        if [[ "$name" == "$current" ]]; then
          mark="*"
          start=$idx
        fi
        text="$(printf '%s%-*s  %s%s' "$mark" "$maxlen" "$name" "$indent" "$label")"

        skey=""
        if ((si < ''${#shortcuts})); then
          skey="''${shortcuts:$si:1}"
          si=$((si + 1))
        fi

        if [[ "$MODE" == "--kill" ]]; then
          cmd="confirm-before -p \"kill =$name? (y/n)\" \"kill-session -t '=$name' ; run-shell -b 'exec $0 --kill'\""
        else
          cmd="switch-client -t '=$name'"
        fi

        # Menu item names are tmux formats — double # so "#123" renders literally.
        args+=("''${text//#/##}" "$skey" "$cmd")
        idx=$((idx + 1))
      done

      # Footer: toggle between switch and kill modes with "x". $0 is the
      # absolute store path of this script, so re-exec is safe from run-shell.
      args+=("")
      if [[ "$MODE" == "--kill" ]]; then
        title=' kill session '
        args+=("← back" "x" "run-shell -b 'exec $0'")
      else
        title=' sessions '
        args+=("✕ kill session…" "x" "run-shell -b 'exec $0 --kill'")
      fi

      # A leading "-" first item would be parsed as a flag by tmux — guard
      # with a separator (only happens when a stack header is the very first
      # line, i.e. the alphabetically-first root session doesn't exist).
      if [[ "''${args[0]}" == -* ]]; then
        args=("" "''${args[@]}")
        start=$((start + 1))
      fi

      if [[ -n "''${WT_MENU_DRY_RUN:-}" ]]; then
        printf '%s\n' "''${args[@]}"
        exit 0
      fi

      exec tmux display-menu -T "$title" -x C -y C -C "$start" "''${args[@]}"
    '';
  };
in
{
  home = {
    home.packages = [
      tmux-wt-refresh
      tmux-wt-menu
    ];
    programs.tmux.extraConfig = ''
      # Stack-aware session menu on prefix+s. The refresh runs in the
      # background while the menu opens instantly with the previous data
      # (self-healing staleness — fresh by the next open).
      bind-key s run-shell -b '${tmux-wt-refresh}/bin/tmux-wt-refresh >/dev/null 2>&1 & exec ${tmux-wt-menu}/bin/tmux-wt-menu'

      # Original native choose-tree picker (same rules) as fallback.
      bind-key S ${choose-tree-picker}

      # Prime metadata when sessions appear. Indexed hook so other modules'
      # global hooks (e.g. opencode-manager) are not clobbered.
      set-hook -g 'session-created[20]' 'run-shell -b "${tmux-wt-refresh}/bin/tmux-wt-refresh"'
    '';
  };
}
