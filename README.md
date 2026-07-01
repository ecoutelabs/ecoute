# Écoute

![Now Playing view](screenshots/mainview.png)

Album-centric local music player for macOS. Browse by album, artist, or song; expand to a full-screen Now Playing view with an animated Metal background and dynamic album art colors. Supports system media controls, lock screen / menu bar integration, and Last.fm scrobbling.

## Features

- **Formats:** MP3, M4A, AAC, FLAC, WAV, AIFF, ALAC, OGG, Opus
- **Library:** recursive folder scan, metadata via TagLib, result caching
- **Browsing:** Albums grid, Artists list, Songs table, with search
- **Now Playing:** full-screen view with animated Metal shader background, scrubber, volume, and Up Next queue
- **System integration:** media keys, lock screen controls, audio device disconnect detection
- **Dynamic theming:** accent colors and background color extracted from album art
- **Last.fm:** scrobbling + Now Playing updates

## Requirements

- macOS with Xcode installed
- Audio files in a folder

## Setup

1. Open `musicplayer/Ecoute.xcodeproj` in Xcode.
2. Scheme: `Ecoute` targeting "My Mac".
3. Run (⌘R) to launch.

Last.fm (optional):
- Copy `musicplayer/Ecoute/resources/configuration/LastFMSecrets.plist.example` to `musicplayer/Ecoute/resources/configuration/LastFMSecrets.plist`.
- Fill in your API key and secret. The real file is `.gitignore`d.

## Building a standalone app

CLI (unsigned local build):
```bash
cd musicplayer
xcodebuild -scheme Ecoute -configuration Release -destination 'generic/platform=macOS' build
cp build/Build/Products/Release/Ecoute.app /Applications/
```

Xcode UI:
1. Open `musicplayer/Ecoute.xcodeproj`.
2. Scheme: `Ecoute`; Destination: `Any Mac (Apple Silicon/Intel)`.
3. Product → Archive.
4. In the Organizer: select the archive → Distribute → Copy App, then save the `.app`.
5. Copy the exported `Ecoute.app` to `/Applications`.

> **Note:** The app is unsigned. On first launch macOS will block it — right-click → Open, or go to System Settings → Privacy & Security → Open Anyway.
