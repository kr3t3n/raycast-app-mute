# Raycast App Mute

Mute, unmute, or toggle audio for **one macOS app** from Raycast (not system-wide mute).

Example: open **Mute App**, type `cli`, select **ClickUp**.

## Requirements

- macOS 14.2 or later
- [Raycast](https://www.raycast.com/)
- Xcode Command Line Tools (to build the Swift helper)

## Install (developer mode)

```sh
git clone https://github.com/kr3t3n/raycast-app-mute.git
cd raycast-app-mute
npm install
npm run agent:build    # installs AppMuteAgent under ~/Library/Application Support/AppMute/
npm run dev            # loads the extension in Raycast developer mode
```

Then in Raycast:

1. Open **Extensions** and enable Developer Mode if needed.
2. Confirm **App Mute** appears.
3. Run **Mute App**, **Unmute App**, or **Toggle App Mute**.
4. When macOS asks, allow **AppMuteAgent** to record system audio in **Privacy & Security**.

The optional **App name** argument only seeds the list filter. You must select a row. The command never mutes the first fuzzy match automatically.

## Commands

| Command | Action |
| --- | --- |
| Mute App | Mute the selected app |
| Unmute App | Unmute the selected app |
| Toggle App Mute | Switch mute state for the selected app |

## How it works

Raycast talks to a local Swift agent over a user-only Unix socket. The agent uses Core Audio process taps (`CATapMuted`) so one app’s output is discarded without changing the system default device.

## Development

```sh
npm run lint
npm test
npm run build
npm run agent:test
```

## Layout

- `src/` — Raycast commands and agent client
- `helper/` — Swift `AppMuteAgent` + installer
- `docs/architecture.md` — design notes
- `icon.png` — extension icon

## License

MIT
