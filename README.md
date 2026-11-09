# Notchprompt

<p align="center">
  <img src="assets/banner.png" alt="Notchprompt Banner" width="100%">
</p>

Native macOS notch-adjacent teleprompter for presentations and recordings.

## Quick Demo

> Demo assets below are placeholders. Replace with real captures before public
> launch.

<!--
![Notchprompt hero screenshot](docs/media/hero.png)
*Hero view of the overlay panel and settings workflow.*

![Notchprompt scrolling demo GIF](docs/media/notchprompt-demo.gif)
*In-use scrolling demo with start/pause and speed adjustments.*
-->

## Features

- A Dynamic Island around the camera: built for the OLED MacBook Pro, and it adapts to the notch and to displays with no camera.
- Pace in words per minute, so the font size never changes how fast you read, and the time shown is the real read time.
- Finish-at-a-set-time mode that works out the pace for you.
- 120 Hz GPU scrolling with a moveable reading line, focus dimming and mirroring.
- Scroll only while you talk, or follow your voice word by word, on device. Choose Apple Speech (macOS 26 and later) or the built-in Whisper model.
- Trackpad correction mid-read, 5-second jump back, optional countdown.
- Import text, Word, RTF, PDF and PowerPoint speaker notes; a searchable script library.
- Hide from screen sharing (`NSWindow.SharingType`, best-effort/app-dependent).

## Requirements

- macOS version supported by the current deployment target in
  `notchprompt.xcodeproj`.
- Apple Silicon or Intel Mac.

## Install (Recommended)

1. Open GitHub Releases:
   `https://github.com/saif0200/notchprompt/releases`
2. Download the latest `.dmg` release asset.
3. Open the DMG and drag `notchprompt.app` to `Applications`.
4. Launch `notchprompt.app`.

### Unsigned Build Note

This build is currently unsigned/unnotarized, so macOS may show security prompts.

If macOS shows:

- `Apple could not verify "notchprompt" is free of malware...`
- or `"notchprompt" is damaged and can’t be opened`

run:

```bash
xattr -cr /Applications/notchprompt.app
open /Applications/notchprompt.app
```

If it is still blocked:

1. Open `System Settings -> Privacy & Security`.
2. Click **Open Anyway** for `notchprompt`.
3. Launch again.

## Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `⌥⌘P` | Start / Pause |
| `⌥⌘R` | Reset scroll |
| `⌥⌘J` | Jump back 5s |
| `⌃⌥⌘H` | Toggle Privacy Mode |
| `⌥⌘=` | Increase speed |
| `⌥⌘-` | Decrease speed |

## Build From Source

```bash
git clone https://github.com/saif0200/notchprompt.git
cd notchprompt
open notchprompt.xcodeproj
```

CLI build:

```bash
xcodebuild -project notchprompt.xcodeproj -scheme notchprompt -configuration Debug build
```

## License

MIT. See `LICENSE`.

## Development

- `zsh scripts/test.sh` runs the logic checks (island geometry, scroll physics, script parsing, voice alignment).
- `zsh scripts/fetch-whisper-model.sh` downloads the Whisper model that ships in the app (`Models/`, gitignored, pinned revision). Release builds fail without it; `install.sh` and `build_release_zip.sh` fetch it for you.
- `NOTCHPROMPT_TEAM=<team id> zsh scripts/install.sh` builds Release, signs it with your Apple Development identity and installs it.
- In a Debug build, `NOTCHPROMPT_SNAPSHOT=<folder>` walks the island through every state, clicks its controls, writes PNGs and quits. The folder must be inside the app's sandbox container. Set `NOTCHPROMPT_DEFAULTS_SUITE=<name>` so it doesn't touch your settings. `NOTCHPROMPT_SPEECH_AUDIO` (16 kHz mono float CAF) and `NOTCHPROMPT_SPEECH_TEXT` also play that speech through each engine in real time and report the lag.
