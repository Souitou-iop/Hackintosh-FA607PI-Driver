#!/bin/bash
# sudo bash airpods-codec.sh eld-off   : DisableAACELD (AirPods fall back to plain AAC); restarts bluetoothd
# sudo bash airpods-codec.sh aac-off   : also DisableAAC (SBC only, like non-Apple headphones)
# sudo bash airpods-codec.sh reset     : remove both keys
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
P=/Library/Preferences/com.apple.Bluetooth
cp $P.plist /var/tmp/com.apple.Bluetooth.plist.bak-$(date +%H%M%S) 2>/dev/null
case "$1" in
  eld-off) defaults write $P DisableAACELD -bool true; defaults delete $P DisableAAC 2>/dev/null;;
  aac-off) defaults write $P DisableAACELD -bool true; defaults write $P DisableAAC -bool true;;
  reset)   defaults delete $P DisableAACELD 2>/dev/null; defaults delete $P DisableAAC 2>/dev/null;;
  *) echo "usage: eld-off|aac-off|reset"; exit 1;;
esac
echo "DisableAACELD=$(defaults read $P DisableAACELD 2>/dev/null || echo unset) DisableAAC=$(defaults read $P DisableAAC 2>/dev/null || echo unset)"
pkill -x bluetoothd; echo "bluetoothd restarted - AirPods reconnect in a few seconds"
