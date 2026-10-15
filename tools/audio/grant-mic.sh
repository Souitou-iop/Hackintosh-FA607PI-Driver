#!/bin/bash
# grant-mic.sh "/path/to/App.app" [service]   - allow the microphone (or kTCCService<service>) for an app whose prompt
# never appears (input methods, background agents, amfi_get_out_of_my_way setups). User TCC.db; backs it up first.
set -euo pipefail
APP=$1; SVC=kTCCService${2:-Microphone}
DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
ID=$(defaults read "$APP/Contents/Info" CFBundleIdentifier)
T=$(mktemp -d); codesign -d -r- "$APP" 2>/dev/null | sed -n 's/^designated => //p' > "$T/req.txt"
[ -s "$T/req.txt" ] && csreq -r "$T/req.txt" -b "$T/req.bin" && HEX=$(xxd -p "$T/req.bin" | tr -d '\n') || HEX=""
cp "$DB" "$DB.bak-$(date +%Y%m%d-%H%M%S)"
CS=$([ -n "$HEX" ] && echo "X'$HEX'" || echo NULL)
sqlite3 "$DB" "INSERT OR REPLACE INTO access (service,client,client_type,auth_value,auth_reason,auth_version,csreq,flags) VALUES ('$SVC','$ID',0,2,3,1,$CS,0);"
sqlite3 "$DB" "select service,client,auth_value,length(csreq) from access where client='$ID';"
killall tccd 2>/dev/null || true
echo "granted $SVC to $ID - quit and reopen the app (input methods: log out and back in, or killall the IME process)"
