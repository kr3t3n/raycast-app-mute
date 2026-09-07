# Raycast App Mute

Mute, unmute, or toggle audio for **one macOS app** from Raycast (not system mute).

Example: open **Mute App**, type `cli`, select **ClickUp**.

Requires **macOS 14.2+**, Raycast, and Xcode Command Line Tools (to build the Swift agent).

## Keep it on (daily use)

Two parts stay installed separately:

1. **AppMuteAgent** — LaunchAgent with `KeepAlive` / `RunAtLoad`. Survives login.
2. **Raycast extension** — stays in Raycast after the first successful `npm run dev` (you can stop the terminal).

```sh
git clone https://github.com/kr3t3n/raycast-app-mute.git
cd raycast-app-mute
npm install
npm run agent:build    # once (or after agent updates)
npm run dev            # once to import/register the extension in Raycast
# Ctrl+C is fine — the extension remains in Raycast
```

Then use **Mute App** / **Unmute App** / **Toggle App Mute** from Raycast root search anytime.

Optional: Raycast → **Import Extension** → select this folder (still run `npm run agent:build`).

When macOS asks, allow **AppMuteAgent** system audio access (Privacy & Security → Screen & System Audio Recording).

## Behaviour

- Mutes one app’s output via Core Audio process taps (other apps stay audible).
- Mute can be **armed while the app is silent**. The agent attaches the tap when that app starts playing audio.
- Menu bar icon (speaker slash / count):
  - Hover lists muted apps
  - Click opens a menu; click an app name to unmute
  - **Unmute All** is also available
- macOS has no public API to badge another app’s Dock icon — use the menu bar indicator instead.

## Commands

| Command | Action |
| --- | --- |
| Mute App | Mute the selected app |
| Unmute App | Unmute the selected app |
| Toggle App Mute | Switch mute state for the selected app |

The optional **App name** argument only seeds the list filter. You must select a row.

## Development

```sh
npm run lint
npm test
npm run build
npm run agent:test
npm run agent:diagnose   # dump mute diagnostics
```

`npm run agent:build` installs:

- `~/Library/Application Support/AppMute/AppMuteAgent.app`
- `~/Library/LaunchAgents/com.kr3t3n.app-mute-agent.plist`
- logs under `~/Library/Logs/AppMute/`

Force-rebuild if the menu bar looks stale:

```sh
launchctl bootout "gui/$(id -u)/com.kr3t3n.app-mute-agent" 2>/dev/null || true
pkill -x AppMuteAgent 2>/dev/null || true
rm -rf helper/.build
npm run agent:build
```

## Layout

- `src/` — Raycast commands and agent client
- `helper/` — Swift AppMuteAgent + installer
- `docs/architecture.md` — design contract

## Store packaging

Personal Import Extension + `agent:build` is the supported path today. Raycast Store publish is possible later, but the native LaunchAgent and system-audio permission make Store review stricter.

## License

MIT
