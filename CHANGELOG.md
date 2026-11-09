# Changelog

## Unreleased

- Whisper now ships inside the app: no download and no network needed to follow your voice.
- Added Apple Speech (macOS 26 and later) as the default engine, with a choice between it and Whisper in Settings.
- Faster voice following: Whisper listens continuously instead of every 0.7 seconds and skips work it never needed.
- The floating island now ends level with the bottom of the camera, with a fine-tune slider in Settings.
- Rebuilt the overlay as a Dynamic Island positioned from the display's measured camera housing, with idle, compact and expanded forms.
- Replaced SwiftUI per-frame rendering with Core Animation scrolling at the display's refresh rate.
- Pace is now words per minute, and read times, the timed mode and the on-screen clock are accurate.
- Fixed reversed natural-scrolling direction, keyboard focus being taken from the frontmost app, and the panel drifting off-centre after a resize.
- Voice: fixed word tracking stopping after 30 seconds, voice scrolling not starting on first enable, a crash with no input device, and the microphone staying on while paused.
- Import: fixed hangs on documents over 64 KB, garbage from binary files, PowerPoint slides out of order past 9, and undecoded XML entities.
- Keeps the 1.1.2 and 1.1.3 work: real-Button controls, macOS 14 and Intel support, paste and clear controls.
- Privacy toggle moved to Control+Option+Command+H so Option+Command+H stays Hide Others.


## 1.1.1 - 2026-02-27

- Fixed shortcut reliability by moving app-wide keyboard shortcuts to Carbon system hotkeys instead of fragile event monitors.
- Added explicit status-menu warnings when one or more shortcuts are unavailable because another app already owns them.
- Fixed pause/resume behavior so scrolling resumes from the current position instead of jumping back to the beginning.

## 1.1.0 - 2026-02-25

- Fixed macOS compatibility packaging/build settings so release artifacts advertise a minimum macOS that includes 15.7.x.
- Fixed settings usability by making the settings content scrollable and reachable at smaller window heights while keeping the window resizable.
- Fixed multi-display behavior so the overlay prefers the built-in MacBook display by default, with user-selected display override and robust fallback to menu-bar screen.
- Added release compatibility check script used in CI to print deployment target and built app minimum system version.
