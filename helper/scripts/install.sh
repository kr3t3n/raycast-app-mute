#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
destination="$HOME/Library/Application Support/AppMute/AppMuteAgent.app"
launch_agents="$HOME/Library/LaunchAgents"
plist="$launch_agents/com.kr3t3n.app-mute-agent.plist"
label="gui/$(id -u)/com.kr3t3n.app-mute-agent"
build="$root/.build/release"
log_dir="$HOME/Library/Logs/AppMute"

swift build -c release --package-path "$root"

rm -rf "$destination"
mkdir -p "$destination/Contents/MacOS" "$launch_agents" "$log_dir"
cp "$build/AppMuteAgent" "$destination/Contents/MacOS/AppMuteAgent"
cp "$build/app-mute-client" "$destination/Contents/MacOS/app-mute-client"
cp "$root/AppMuteAgent-Info.plist" "$destination/Contents/Info.plist"
# Stable ad-hoc signature keeps System Audio TCC attached across rebuilds.
codesign --force --deep --sign - --identifier com.kr3t3n.app-mute-agent "$destination" >/dev/null 2>&1 || true
sed \
  -e "s|__AGENT_PATH__|$destination/Contents/MacOS/AppMuteAgent|" \
  -e "s|__LOG_DIR__|$log_dir|" \
  "$root/com.kr3t3n.app-mute-agent.plist" > "$plist"

launchctl bootout "$label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
launchctl enable "$label" 2>/dev/null || true
launchctl kickstart -k "$label"

echo "Installed and started AppMuteAgent."
echo "Logs: $log_dir/agent.log"