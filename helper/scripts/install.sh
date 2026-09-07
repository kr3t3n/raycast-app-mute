#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
destination="$HOME/Library/Application Support/AppMute/AppMuteAgent.app"
launch_agents="$HOME/Library/LaunchAgents"
build="$root/.build/release"
swift build -c release --package-path "$root"
rm -rf "$destination"
mkdir -p "$destination/Contents/MacOS" "$launch_agents"
cp "$build/AppMuteAgent" "$destination/Contents/MacOS/AppMuteAgent"
cp "$build/app-mute-client" "$destination/Contents/MacOS/app-mute-client"
cp "$root/AppMuteAgent-Info.plist" "$destination/Contents/Info.plist"
sed "s|__AGENT_PATH__|$destination/Contents/MacOS/AppMuteAgent|" "$root/com.kr3t3n.app-mute-agent.plist" > "$launch_agents/com.kr3t3n.app-mute-agent.plist"
launchctl bootstrap "gui/$(id -u)" "$launch_agents/com.kr3t3n.app-mute-agent.plist" 2>/dev/null || true
echo "Installed AppMuteAgent."
