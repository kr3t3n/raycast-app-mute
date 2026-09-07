# Raycast App Mute

Mute, unmute, or toggle audio for **one macOS app** from Raycast (not system mute).

Public repo: https://github.com/kr3t3n/raycast-app-mute

Example: open **Mute App**, type `cli`, select **ClickUp**.

Requires macOS 14.2+, Raycast, and Xcode Command Line Tools (to build the Swift agent).

## Install on your Mac

From the public clone (or this folder after you sync `claude-env`):

```sh
git clone https://github.com/kr3t3n/raycast-app-mute.git
cd raycast-app-mute
# or: cd ~/claude-env/personal/projects/raycast-app-mute
git pull
npm install
npm run agent:build    # builds AppMuteAgent into ~/Library/Application Support/AppMute/
npm run dev            # uses `ray develop` from @raycast/api
```

Requires macOS 14.2+ (Sonoma). The Swift helper uses Core Audio process taps.

Then in Raycast:

1. Open **Extensions** and enable Developer Mode if needed.
2. Confirm **App Mute** appears.
3. Run **Mute App**, **Unmute App**, or **Toggle App Mute**.
4. When macOS asks, allow **AppMuteAgent** to record system audio (Privacy & Security).

The optional **App name** argument only seeds the list filter. You must select a row. The command never mutes the first fuzzy match automatically.

## Commands

| Command | Action |
| --- | --- |
| Mute App | Mute the selected app |
| Unmute App | Unmute the selected app |
| Toggle App Mute | Switch mute state for the selected app |

## Development (Mac)

```sh
npm run lint
npm test
npm run build
npm run agent:test
```

`npm run agent:build` installs a user LaunchAgent and a mode `0600` control socket. It does not change the default audio output device.

## Layout

- `src/` — Raycast commands and agent client
- `helper/` — Swift AppMuteAgent + installer
- `docs/architecture.md` — design contract
- `icon.png` — extension icon
