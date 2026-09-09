#!/bin/bash
# Emergency stop: release mutes by killing AppMuteAgent (taps die with the process).
set -euo pipefail
label="gui/$(id -u)/com.kr3t3n.app-mute-agent"
launchctl bootout "$label" 2>/dev/null || true
pkill -x AppMuteAgent 2>/dev/null || true
sleep 1
if pgrep -x AppMuteAgent >/dev/null; then
  echo "AppMuteAgent still running; try: killall -9 AppMuteAgent"
  exit 1
fi
echo "AppMuteAgent stopped. Existing Core Audio taps are released."
echo "If Chrome is still silent: Quit Chrome (Cmd+Q), then: sudo killall coreaudiod"
echo "Then reopen Chrome and test audio."
