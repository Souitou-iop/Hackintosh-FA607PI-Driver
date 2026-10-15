#!/bin/bash
# Write DisableAACELD into every domain bluetoothd (root) may read, restart bluetoothd. "reset" removes them.
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
for dom in com.apple.bluetooth com.apple.bluetoothd com.apple.BluetoothAudioAgent /Library/Preferences/com.apple.bluetoothd /Library/Preferences/com.apple.Bluetooth; do
  if [ "${1:-}" = reset ]; then defaults delete $dom DisableAACELD 2>/dev/null; else defaults write $dom DisableAACELD -bool true; fi
  echo "$dom: $(defaults read $dom DisableAACELD 2>/dev/null || echo unset)"
done
pkill -x bluetoothd; echo "bluetoothd restarted"
