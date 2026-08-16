#!/usr/bin/env bash

# guest-mode: hand the laptop to someone else without the Hyper layer
# confusing them.
#
# Hammerspoon owns every custom binding on this machine, and the whole Hyper
# layer is reachable only through the hidutil Caps Lock -> F18 remap. Holding
# Caps Lock to type an acronym is a normal habit, and on this machine it fires
# Hyper actions instead: "SLACK" opens Slack, jumps focus to nvim and moves the
# cursor. Guest mode drops both halves of that:
#
#   on   Clears the hidutil map (Caps Lock acts like Caps Lock again) and
#        quits Hammerspoon (no Hyper bindings, no alerts).
#   off  Restores the map and relaunches Hammerspoon.
#
# Clearing hidutil is the part that matters. Quitting Hammerspoon on its own is
# actively worse than doing nothing: the key still emits F18, nothing listens
# for it any more, and Caps Lock ends up dead.
#
# ponytail: clearing the hidutil map alone already makes every Hyper binding
# unreachable, since they all key off F18. Hammerspoon is quit as well only so
# its "mapping lost" alert in init.lua can't pop up in front of a guest. If that
# alert ever goes away, this can drop to a single hidutil call each way.
#
# Usage: guest-mode on|off|toggle   (no argument toggles)

# Caps Lock (0x700000039) -> F18 (0x70000006D). Must stay in sync with
# system.keyboard.userKeyMapping in hammerspoon.nix.
CAPS_TO_F18='{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}'

# Hammerspoon not running is the observable signal that guest mode is active.
# If Hammerspoon crashed on its own this reads as "guest mode on", and toggling
# then relaunches it — which is the right recovery either way.
guest_is_on() {
  ! /usr/bin/pgrep -x Hammerspoon >/dev/null 2>&1
}

enable_guest() {
  # hidutil first. Quitting Hammerspoon can tear down the shell running this
  # script, and stopping half way leaves Caps Lock dead - the exact failure
  # this script exists to prevent.
  /usr/bin/hidutil property --set '{"UserKeyMapping":[]}' >/dev/null
  /usr/bin/osascript -e 'quit app "Hammerspoon"' >/dev/null 2>&1
  echo "guest mode ON - stock keyboard, no Hyper layer"
}

disable_guest() {
  /usr/bin/hidutil property --set "$CAPS_TO_F18" >/dev/null
  /usr/bin/open -a Hammerspoon
  echo "guest mode OFF - Hyper layer restored"
}

case "${1:-toggle}" in
  on) enable_guest ;;
  off) disable_guest ;;
  toggle)
    if guest_is_on; then
      disable_guest
    else
      enable_guest
    fi
    ;;
  *)
    echo "Usage: guest-mode on|off|toggle"
    exit 1
    ;;
esac
