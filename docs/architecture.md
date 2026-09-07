# Raycast App Mute architecture

Status: Proposed for MUTE-2  
Scope: Architecture only  
Minimum target: macOS 14.2

## Decision summary

The extension will provide three Raycast view commands: Mute App, Unmute App, and Toggle App Mute.

Each command will show a searchable app list. The list will use running apps by default. It will rank apps with active audio above other running apps.

A packaged Swift agent will control audio. It will use Apple Core Audio process taps with `CATapMuted`. The user will not need another audio utility.

The agent will remain active while one or more apps are muted. The agent will remove its taps when it stops. This fail-open behavior restores normal audio after an agent failure.

## System boundary

```text
Raycast TypeScript command
  |  JSON request through a local user-only socket
  v
AppMuteAgent.app and command-line client
  |  app and process discovery
  |  mute registry
  v
Core Audio HAL process taps
  |
  v
Selected app output is discarded; other app output is unchanged
```

Raycast owns the list, search, actions, toasts, and preferences. The native agent owns process discovery, mute state, and Core Audio resources.

The control socket will use the current user account only. It will not open a TCP port. The socket file will have mode `0600`.

## Raycast extension shape

### Commands

| Command | Mode | Primary action | Default list |
| --- | --- | --- | --- |
| Mute App | `view` | Mute the selected app | Apps with audio, then other running apps |
| Unmute App | `view` | Unmute the selected app | Muted apps, then other running apps |
| Toggle App Mute | `view` | Change the selected app state | Muted apps, apps with audio, then other running apps |

All commands will use the same list component and action service. This design prevents different matching and error behavior between commands.

The primary action will be idempotent. Mute on a muted app will report “ClickUp is already muted.” Unmute on an unmuted app will report the equivalent state.

Toggle will read state from the agent before it changes the state. It will not infer state from an icon or cached Raycast data.

### Arguments and autocomplete

Each command will define one optional text argument named `appQuery`. The placeholder will be `App name`. The argument will seed the list search when the command opens.

For example, the user can select Mute App, type `cli`, and press Return. The opened list will put ClickUp first when it is a valid candidate.

Raycast command arguments do not support dynamic data. Raycast supports text, password, and static dropdown arguments. A static dropdown cannot represent a changing app list. See the [Raycast arguments documentation](https://developers.raycast.com/information/lifecycle/arguments) and [manifest reference](https://developers.raycast.com/information/manifest).

Therefore, live app suggestions will appear in the command list. They will not appear under the root-search argument while the user types. This is the closest supported Raycast extension flow.

The command will never act on the first fuzzy match without confirmation. The user must select a row and press Return. This rule prevents an ambiguous query from muting the wrong app.

### Preferences

| Preference | Type | Default | Purpose |
| --- | --- | --- | --- |
| Candidate Apps | Dropdown | Running Apps | Select running apps only, or running and installed apps |
| Include Background Apps | Checkbox | Off | Include agents and apps without a normal user interface |
| Close After Action | Checkbox | On | Close Raycast after a successful action |

The extension will not expose a utility path. MUTE-2 will package the selected backend. A development build can use an environment override, but this is not a user preference.

An `appPicker` preference is not suitable. It selects one fixed app in settings. The user needs a different app for each command run.

## App discovery and matching

### Data sources

Raycast will call `getApplications()` to list installed apps. This API returns the app name, path, and bundle identifier. See [Raycast system utilities](https://developers.raycast.com/api-reference/utilities).

The Swift agent will return running and audio process data. It will use these macOS sources:

- `NSWorkspace.shared.runningApplications` for running app identity.
- `AudioHardwareSystem.shared.processes` for Core Audio client processes.
- `AudioHardwareProcess.isRunningOutput` for active output state.

Apple documents [running applications](https://developer.apple.com/documentation/appkit/nsworkspace/runningapplications) and [Core Audio processes](https://developer.apple.com/documentation/coreaudio/audiohardwareprocess).

The extension will merge records by bundle identifier. It will use the normalized outer app path when a bundle identifier is absent. A Raycast row will use the bundle identifier as its stable key when possible.

### App groups

One visible app can own several audio processes. Electron apps and browsers often use nested helper processes.

The agent will group an audio process with its outer application bundle when its executable sits inside that bundle. It will use the parent-process chain as a fallback. It will return every matched Core Audio process ID in one app record.

The selected identity will be the app group, not one process ID. Mute will affect all current audio processes in that group. The agent will add later matching processes while the mute remains active.

This grouping is required for ClickUp. A ClickUp audio helper must appear under ClickUp, not as an unrelated helper row.

### Candidate order

The default command list will contain these sections:

1. Muted.
2. Playing Audio.
3. Running.
4. Installed, when the preference enables this section.

Mute App will omit an empty Muted section. Unmute App will put muted apps first. The extension will hide duplicate records across sections.

Installed but closed apps cannot have a current audio session. Their rows will show `Not running`. Mute and Toggle will not start an app without a separate user action.

### Fuzzy matching

The implementation will use Raycast `List` filtering first. Raycast performs fuzzy matching on each item title and its keywords. See the [Raycast List documentation](https://developers.raycast.com/api-reference/user-interface/list).

Each item will use these indexed values:

- Display name and localized name.
- Bundle identifier.
- Executable name.
- Known outer-app name for helper processes.

The list will preserve the section order. It will not add Fuse.js unless acceptance tests show a matching defect.

The query `cli` must rank ClickUp before non-prefix matches. An exact name match must rank first. A bundle identifier query must also find the app.

## Per-app mute mechanism

### Options

| Option | Benefits | Costs and risks | Decision |
| --- | --- | --- | --- |
| Apple Core Audio process taps | Uses a public Apple API. Needs no audio driver or separate utility. | Requires macOS 14.2 or later, native code, a long-running process, and system audio permission. | Default |
| Background Music | Provides open-source per-app volume control. | Requires a separate app and virtual audio driver. It changes the default output device. The project labels itself alpha. | Do not require |
| Existing audio mixer | Products such as SoundSource and Waves already provide per-app control. | Requires a separate install. Licensing and automation interfaces differ. | Optional future backend |
| Private Core Audio API or UI automation | Could reduce native helper code. | Can break after a macOS update. UI automation needs Accessibility permission. | Reject |

[Background Music](https://github.com/kyleneideck/BackgroundMusic) documents its virtual-device design. [SoundSource](https://www.rogueamoeba.com/support/manuals/soundsource/?page=application-adjustments) documents its per-app controls.

### Default mechanism

Apple provides process taps in macOS 14.2 and later. A tap can capture one or more process outputs and prevent that output from reaching audio hardware. See [Apple’s Core Audio tap sample](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) and [`CATapMuteBehavior`](https://developer.apple.com/documentation/coreaudio/catapmutebehavior).

For each muted app group, the agent will take these logical steps:

1. Resolve the current Core Audio process object IDs.
2. Create a private stereo process tap for those IDs.
3. Set `muteBehavior` to `CATapMuted`.
4. Leave `deviceUID` unset so the tap is not limited to one hardware device.
5. Add the tap to one private aggregate capture device.
6. Start one input callback and discard all received samples.
7. Keep the tap and callback active until Unmute.

Apple states that a missing `deviceUID` means the tap is not limited to one hardware device. See [`CATapDescription.deviceUID`](https://developer.apple.com/documentation/coreaudio/catapdescription/deviceuid).

The agent will use one aggregate device for its active taps. It will update the aggregate tap list when mute state changes. It will destroy a removed tap only after the aggregate no longer uses it.

The agent will keep this in-memory state for each app group:

- Bundle identifier and outer app path.
- Current process IDs and Core Audio process object IDs.
- Tap identifier and aggregate membership.
- Requested state and last Core Audio error.

The agent is the state authority. Raycast LocalStorage can cache display data, but it cannot define mute state.

Mute state will survive Raycast command exit. It will not survive agent exit or user logout. The agent will not restore muted apps after login in MUTE-2.

### Process changes

The agent will listen for changes to the Core Audio process list. It will update an active app group when a matching helper process starts or stops.

If all target processes stop, the agent will keep the requested app state for 30 seconds. This interval covers short helper restarts. It will then remove the tap and clear the mute record.

The exact grace interval should be one constant with a unit test. MUTE-2 will not expose it as a preference.

### Control protocol

The Raycast code will call a small command-line client. The client will communicate with the agent through the local socket.

The protocol will support these operations:

- `health`: Return protocol version, agent version, permission state, and macOS support state.
- `list`: Return merged running, audio, and mute state.
- `set`: Set one app group to muted or unmuted.
- `toggle`: Change one app group after an atomic state read.
- `stop`: Stop the agent and release all taps.

Each response will contain a stable code, a short message, and optional data. The extension will not parse localized error text.

## User experience

Each app row will show the app icon and name. It will show one state label: `Muted`, `Playing Audio`, `No Audio Session`, or `Not Running`.

Mute and Toggle need an active Core Audio process, unless that app already has a mute record. Unmute only needs an existing mute record.

After success, Raycast will show a HUD such as `Muted ClickUp`. It will close the window when Close After Action is on.

The extension will keep the command open after a failure. It will show a failure toast with one corrective action.

| Condition | Message | Corrective action |
| --- | --- | --- |
| App is not running | `ClickUp is not running.` | Offer Open Application |
| No Core Audio process exists | `ClickUp has no audio session.` | Ask the user to play audio and try again |
| App stopped after selection | `ClickUp stopped before the action.` | Refresh the list |
| Permission is not granted | `Allow system audio access for AppMuteAgent.` | Open the correct Privacy & Security pane |
| Agent cannot start | `AppMuteAgent could not start.` | Offer setup or reinstall instructions |
| macOS is too old | `App mute needs macOS 14.2 or later.` | Do not offer the action |
| Core Audio rejects the tap | `macOS could not mute ClickUp.` | Show the stable error code and allow retry |

The UI will not show `Muted` until the agent confirms tap activation. Unmute will report success only after the tap is removed.

## Packaging and installation

MUTE-2 will remain a personal extension. Raycast Store publication is outside its scope.

The project will contain a TypeScript Raycast package and a native Swift agent target. The release build will produce a universal `arm64` and `x86_64` agent app.

The package will install the native app at:

`~/Library/Application Support/AppMute/AppMuteAgent.app`

It will install a per-user launch agent at:

`~/Library/LaunchAgents/com.kr3t3n.app-mute-agent.plist`

The control socket and non-secret state will use:

`~/Library/Application Support/AppMute/`

The Raycast extension will start the launch agent on demand. The launch agent will not set `KeepAlive` to true. The agent will exit after an idle interval when no app is muted.

The extension and agent will perform a protocol-version handshake. An extension update will refuse an incompatible agent and offer a reinstall action.

The installer must preserve a stable bundle identifier and code-signing identity. This reduces repeated permission prompts. Public distribution would also require Developer ID signing and notarization.

The uninstaller will stop the launch agent, release all taps, remove the launch-agent file, and remove the installed agent app. It will not change system output settings.

## macOS permissions

The native agent will include `NSAudioCaptureUsageDescription` in its `Info.plist`. Apple requires this key for Core Audio taps.

The first active tap will cause macOS to request system audio recording access. The System Settings label can vary by macOS version. It is normally under Privacy & Security and Screen & System Audio Recording.

The permission belongs to the stable native agent bundle. It does not belong to each short Raycast command process.

The default design does not need these permissions:

- Administrator access.
- Accessibility.
- Automation or Apple Events.
- Microphone input.
- A system extension or audio driver.

The helper must detect denied and restricted permission states. It must return a specific error instead of waiting without a time limit.

## MUTE-2 acceptance criteria

MUTE-2 is ready for review when all criteria below pass on a supported Mac.

### Extension behavior

- The project contains Mute App, Unmute App, and Toggle App Mute commands.
- Each command accepts an optional `appQuery` text argument.
- The argument seeds the in-command app search.
- Typing `cli` ranks ClickUp first when ClickUp is a valid candidate.
- The list groups muted, playing, running, and optional installed apps without duplicates.
- Search finds an app by name, executable name, or bundle identifier.
- Mute and Unmute are idempotent.
- Toggle uses the agent’s confirmed state.
- The extension never acts on an unconfirmed fuzzy match.

### Audio behavior

- Muting one test app makes that app silent.
- A second playing app remains audible during the test.
- Unmute restores the selected app without restarting it.
- Toggle completes two full mute and unmute cycles.
- ClickUp helper audio maps to the ClickUp app group when ClickUp produces audio.
- An app without a Core Audio session returns `NO_AUDIO_SESSION`.
- Stopping the native agent releases all mutes.
- A process exit removes its stale Core Audio resources after the grace interval.
- A default-output change does not leave an app falsely marked as muted.

### Setup and failure behavior

- A clean setup does not require an existing audio utility.
- The build produces a universal native agent.
- The installer uses the documented user paths.
- The first-use flow explains and requests system audio access.
- A denied permission produces a specific error and a settings action.
- macOS versions before 14.2 show an unsupported message.
- The control socket accepts requests from the current user only.
- An incompatible protocol version produces a reinstall action.

### Validation

- TypeScript tests cover app merging, grouping presentation, action selection, and stable error mapping.
- Swift tests cover mute-registry transitions, idempotency, process grouping, and stale-process cleanup.
- `npm run lint`, `npm run build`, and all automated tests pass.
- Manual tests cover built-in speakers and one changed output device.
- Manual results record the macOS version, CPU architecture, and tested apps.

## Open questions and risks

### Root-search autocomplete

Raycast cannot supply live values for a text argument. Confirm whether the seeded in-command list meets the intended `mute cli…` workflow.

If root-search suggestions are mandatory, the requirement depends on a future Raycast API. MUTE-2 must not create a stale generated dropdown as a substitute.

### Minimum macOS version

The default is macOS 14.2 because Apple introduced the required process taps there. Confirm that dropping older macOS versions is acceptable.

### Signing identity

A stable native signature helps preserve the system audio permission. Confirm whether MUTE-2 can use a local Apple Development identity or needs Developer ID packaging.

### App lifetime

The default does not restore mute state after agent exit or login. Confirm whether later work should persist desired mute state across login.

### Helper-process attribution

Electron and browser helpers can use unexpected bundle identifiers and parent chains. MUTE-2 must test ClickUp. Other complex apps can require explicit mapping rules.

### Multiple output devices

The design leaves `deviceUID` unset to cover all output devices. Aggregate devices, Multi-Output Device, AirPlay, Bluetooth, and app-specific routing still need manual tests.

The agent must prefer a clear failure over a partial mute. It must not report success when one known target process remains audible.

### Protected and low-latency audio

Some protected media, conferencing apps, digital audio workstations, or exclusive devices can reject taps. The extension needs stable errors and a safe cleanup path.

### Store distribution

Raycast Store review can restrict bundled executables and installers. MUTE-2 targets personal installation. Store support needs a separate packaging decision.
