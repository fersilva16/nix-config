# shellcheck shell=bash
# tmux side of the omo notifier: reads the pane options tmux-notifier.ts
# publishes. Only panes still running omo count, so options a crashed omo left
# behind are ignored.
#   goto [client-tty]  prefix+N: jump to the newest pane that needs you and
#                      clear it, so pressing it again walks the rest
#   dismiss <window>   clear attention on a window you just looked at
#   widget             status-bar pill: busy sessions and pending attention

live='#{==:#{pane_current_command},omo}'

case "${1:-}" in
  goto)
    pane=$(tmux list-panes -a -f "#{&&:$live,#{@agent-attn}}" -F '#{@agent-attn-at} #{pane_id}' | sort -rn | awk 'NR == 1 { print $2 }')
    # Most commands name the client with -c, refresh-client with -t (its -c
    # is a flag). tmux parses a whole chain first, so one bad flag drops it all.
    client=() target=()
    [[ -n "${2:-}" ]] && client=(-c "$2") target=(-t "$2")
    if [[ -z "$pane" ]]; then
      tmux display-message "${client[@]}" "No notifications"
      exit 0
    fi
    # switch-client to a pane also selects its window and the pane itself.
    tmux set-option -pu -t "$pane" @agent-attn \; set-option -pu -t "$pane" @agent-attn-at \; \
      switch-client "${client[@]}" -t "$pane" \; refresh-client "${target[@]}" -S
    ;;

  dismiss)
    # The window can be gone by the time this runs; nothing to clear then.
    for pane in $(tmux list-panes -t "$2" -f '#{@agent-attn}' -F '#{pane_id}' 2>/dev/null); do
      tmux set-option -pu -t "$pane" @agent-attn \; set-option -pu -t "$pane" @agent-attn-at
    done
    ;;

  widget)
    read -r busy attn < <(tmux list-panes -a -f "$live" -F '#{@agent-status}|#{@agent-attn}' 2>/dev/null |
      awk -F'|' '$1 == "busy" { b++ } $2 != "" { a++ } END { print b + 0, a + 0 }')
    ((busy + attn > 0)) || exit 0

    # Flexoki: orange when something needs you, purple otherwise.
    bg="#f2f0e5" white="#fffcf0" badge="#8b7ec8"
    ((attn > 0)) && badge="#da702c"
    body=""
    ((busy > 0)) && body+="#[fg=$white,bg=$badge,bold]  $busy"
    ((attn > 0)) && body+="#[fg=$white,bg=$badge,bold]  $attn"
    # Powerline rounded ends form a pill:  on the left,  on the right.
    echo "#[fg=$badge,bg=$bg]$body #[fg=$badge,bg=$bg]#[fg=#100f0f,bg=$bg,nobold,noitalics,nounderscore,nodim] "
    ;;

  *)
    echo "usage: tmux-agent-notify goto [client-tty] | dismiss <window> | widget" >&2
    exit 2
    ;;
esac
