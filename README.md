# Mac Mic Mute

A simple macOS menu bar app that mutes/unmutes all microphones system-wide.

<img width="412" height="268" alt="screenshot" src="https://github.com/user-attachments/assets/deea9884-e0b8-423c-954e-ac16b6e1a792" />

## Features

- **Menu bar icon**: Shows mic status (🎤 active / 🎤🚫 muted)
- **Global hotkey**: `⌘⇧M` (Cmd+Shift+M) to toggle mute from anywhere
- **All microphones**: Mutes built-in, USB, and external mics (including Sennheiser Profile, webcams, etc.)
- **System-level**: Works as an override for video calls (Google Meet, Teams, Zoom)

## Usage

### Preferred install (Homebrew):
```bash
brew tap jcleigh/mac-mic-mute
brew install --cask jcleigh/mac-mic-mute/mac-mic-mute
```

### Run directly from source:
```bash
swift build -c release
.build/release/MacMicMute
```

### Run as app bundle:
```bash
open "Mac Mic Mute.app"
```

### Install local app bundle to Applications:
```bash
cp -r "Mac Mic Mute.app" /Applications/
```

## Permissions

The app may require **Accessibility** permissions for global hotkey support:
- System Preferences → Security & Privacy → Privacy → Accessibility
- Add the app to the list

## Building

```bash
swift build -c release
```

## How it works

Uses CoreAudio APIs to:
1. Enumerate all audio input devices
2. Toggle hardware mute if supported
3. Fall back to setting volume to 0 for devices without hardware mute

The app runs as a menu bar-only app (no dock icon) with `LSUIElement` set to true.
