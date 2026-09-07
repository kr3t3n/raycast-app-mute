#!/bin/bash
set -euo pipefail
client="$HOME/Library/Application Support/AppMute/AppMuteAgent.app/Contents/MacOS/app-mute-client"
query="${1:-ClickUp}"
payload=$(printf '{"protocolVersion":1,"operation":"diagnose","appId":"%s"}' "$query" | base64)
"$client" "$payload"
echo
echo "--- last-action.json ---"
cat "$HOME/Library/Application Support/AppMute/last-action.json"
