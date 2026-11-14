#!/usr/bin/env bash

# The DualSense keeps a single Bluetooth host: pairing it with the PS5 voids
# the key this machine stored, so the old entry must go before pairing again.
find_dualsense() {
  bluetoothctl devices | awk '/^Device .* DualSense/ && !found { print $2; found = 1 }'
}

while read -r old; do
  bluetoothctl remove "$old" >/dev/null
done < <(bluetoothctl devices | awk '/^Device .* DualSense/ { print $2 }')

echo 'Hold Create + PS until the light bar double-blinks...'
addr=
for _ in $(seq 30); do
  bluetoothctl --timeout 1 scan on >/dev/null
  addr=$(find_dualsense)
  if [ -n "$addr" ]; then
    break
  fi
done

if [ -z "$addr" ]; then
  echo 'No DualSense found. Is the light bar double-blinking?' >&2
  exit 1
fi

bluetoothctl pair "$addr"
bluetoothctl trust "$addr"
bluetoothctl connect "$addr"
