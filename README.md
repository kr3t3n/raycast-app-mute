# Raycast App Mute

Mute, unmute, or toggle audio for **one macOS app** from Raycast (not system mute).

Public repo: https://github.com/kr3t3n/raycast-app-mute

Example: open **Mute App**, type `cli`, select **ClickUp**.

Requires macOS 14.2+, Raycast, and Xcode Command Line Tools (to build the Swift agent).

## Keep it on (daily use)

Two parts stay installed separately:

1. **AppMuteAgent** — LaunchAgent with `KeepAlive` / `RunAtLoad`. Survives logout restart of the agent and login.
2. **Raycast extension** — stays in Raycast after the first successful `npm run dev` (you can stop the terminal).

```sh
cd ~/claude-env/personal/projects/raycast-app-mute   # or the public clone
git pull
npm install
npm run agent:build    # once (or after agent updates)
npm run dev            # once to import/register the extension in Raycast
# Ctrl+C is fine — the extension remains in Raycast
```

Then use **Mute App** / **Unmute App** / **Toggle App Mute** from Raycast root search anytime.

Optional permanent import without leaving a terminal open:

1. Raycast → **Import Extension**
2. Select this folder
3. Still run `npm run agent:build` so the LaunchAgent is installed

Menu bar: the agent shows **♪** when nothing is muted, and **🔇N** when N apps are muted. The menu lists muted apps and can unmute them.

Dock icons: macOS has no public API to badge or overlay another app’s Dock icon. Use the menu bar indicator instead.

## Raycast Store packaging

Yes, this can become a “real” Store extension later (`npm run build` / Raycast publish flow). Store review is separate: the native LaunchAgent + system-audio permission needs clear setup docs, and Store rules around bundled helpers are stricter than a personal import. For personal use, Import Extension + `agent:build` is the supported path today.

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

## Layout

- `src/` — Raycast commands and agent client
- `helper/` — Swift AppMuteAgent + installer
- `docs/architecture.md` — design contract
