#!/bin/bash
set -euo pipefail
client="$HOME/Library/Application Support/AppMute/AppMuteAgent.app/Contents/MacOS/app-mute-client"
query="${1:-ClickUp}"
payload=$(printf '{"protocolVersion":1,"operation":"diagnose","appId":"%s"}' "$query" | base64)
"$client" "$payload"
echo
echo "=== last-action.json ==="
cat "$HOME/Library/Application Support/AppMute/last-action.json" 2>/dev/null || true
echo
echo "=== latest-log.txt (tail) ==="
tail -n 80 "$HOME/Library/Application Support/AppMute/latest-log.txt" 2>/dev/null || true
echo
echo "=== agent.log (tail) ==="
tail -n 80 "$HOME/Library/Logs/AppMute/agent.log" 2>/dev/null || true
echo
echo "=== raycast.log (tail) ==="
tail -n 40 "$HOME/Library/Logs/AppMute/raycast.log" 2>/dev/null || true
