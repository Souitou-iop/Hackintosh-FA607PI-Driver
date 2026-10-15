#!/bin/bash
# AirPods no sound on Intel BT: bluetoothd picks Apple's vendor AAC-ELD codec, which stays silent here.
# bluetoothd reads A2DP debug switches from com.apple.MobileBluetooth.debug -> A2DP -> DisableAACELD.
#   sudo bash airpods-codec3.sh on | aac-off | reset
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
for dom in /Library/Bluetooth/Library/Preferences/com.apple.MobileBluetooth.debug /Library/Preferences/com.apple.MobileBluetooth.debug; do
  case "${1:-on}" in
    on)      defaults write $dom A2DP -dict-add DisableAACELD -bool true ;;
    aac-off) defaults write $dom A2DP -dict-add DisableAACELD -bool true; defaults write $dom A2DP -dict-add DisableAAC -bool true ;;
    reset)   defaults delete $dom A2DP 2>/dev/null ;;
  esac
  echo "$dom: $(defaults read $dom A2DP 2>/dev/null | tr -d '\n ' || echo unset)"
done
# undo the earlier top-level attempts (they only affected HFP)
for dom in /Library/Preferences/com.apple.Bluetooth com.apple.bluetooth com.apple.bluetoothd com.apple.BluetoothAudioAgent /Library/Preferences/com.apple.bluetoothd; do defaults delete $dom DisableAACELD 2>/dev/null; defaults delete $dom DisableAAC 2>/dev/null; done
pkill -x bluetoothd; echo "bluetoothd restarted - reconnect the AirPods"
