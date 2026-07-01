# Ecoute — Feature Reference

A focused, album-centric music player for macOS with deep system integration and Last.fm scrobbling.

---

## Audio Playback

**Formats supported:** MP3, M4A, AAC, FLAC, WAV, AIFF, ALAC, OGG, Opus (via AVFoundation)

**Transport controls:**
- Play / Pause
- Next track and previous track
- Scrubbing — direct seek to any position; UI updates immediately for responsiveness, then confirmed by AVPlayer callback
- Volume slider (0–100%), controlling the app's AVPlayer volume

**Playback behavior:**
- Tracks advance automatically at end; playback stops at the end of an album (no loop)
- User-initiated next track wraps around to the beginning of the album (modulo); auto-advance stops at the last track
- Previous track goes to the preceding track (floors at index 0, no wrap)
- Switching to a new album starts from the first track
- Playback pauses automatically when the audio output device is disconnected (CoreAudio `AudioObject` property listener)

**Keyboard:** Spacebar toggles play/pause when no text field (`NSTextField`, `NSTextView`) is focused. Disabled when Cmd, Option, or Control is held. Implemented via `NSEvent.addLocalMonitorForEvents` in `SpacebarToggleManager` (`ContentView.swift`).

---

## Library

**Scanning:**
- Scans a user-selected folder recursively for audio files
- Groups tracks in the same directory into albums
- Extracts metadata via TagLib (C library through `CXXTagLib` SPM package): title, artist, album artist, album, track/disc numbers, year, original year, duration, artwork, compilation flag, MusicBrainz IDs, and sort fields (`TITLESORT`, `ARTISTSORT`, `ALBUMSORT`, `ALBUMARTISTSORT`)
- Results cached with a file-modification signature so unchanged folders are skipped (`~/Library/Caches/LocalAlbumLibraryCache/`)
- Rescan and Rescan & Clear Cache available in Settings

**Album artist resolution** (in priority order):
1. Explicit `ALBUMARTIST` tag
2. `RELEASETYPE` compilation tag or "Various Artists" album artist → "Various Artists"
3. Majority artist (≥60% of tracks share the same artist)
4. Folder-name parsing (`"Artist - Album"` format)
5. "Unknown Artist"

**Track ordering:** disc number → track number → title sort key

**Sort keys:** Tags like `ALBUMSORT` are respected so articles sort correctly (e.g., "The Wall" sorts under W)

**Persistence:** Library folder remembered across launches via a security-scoped bookmark stored in `UserDefaults`

---

## Browsing

The sidebar (`LibrarySidebar.swift`) has a Library section with three rows — Albums, Artists, Songs — plus a search bar (`.searchable` attached to the sidebar). The selected section drives `AppViewModel.selectedSection: LibrarySection` (enum: `.albums`, `.artists`, `.songs`). `ContentView` switches the main content area based on this value.

**Albums view (`AlbumGridView`):** Adaptive `LazyVGrid` of album cards (160–220 px wide). Each card shows cover art, title, artist, and year. The currently playing album gets a white border highlight. Tapping a card calls `viewModel.selectBrowsingAlbum(_:)`, which sets `browsingAlbum` and asynchronously extracts accent colors for that album.

**Artists view (`ArtistListView`):** `LazyVStack` with pinned section headers. Each artist section has a header row (expand/collapse chevron, waveform icon if that artist is currently playing) and an album grid beneath it when expanded. Expansion state is tracked in `AppViewModel.expandedArtists: Set<String>`. During search, artists with matching albums auto-expand (controlled by `collapsedSearchOverrides`). `artistToScrollTo` triggers a programmatic scroll via `ScrollViewReader`.

**Songs view (`SongListView`):** Table with Title, Artist, Album, and Time columns. Waveform icon on the currently playing track. Backed by `AppViewModel.allTracks()` which filters and sorts the full track list.

**Album detail view (`AlbumDetailView`):** Shown when `browsingAlbum` is set. Displays large cover art (220×220 px), album title, artist (tapping calls `viewModel.navigateToArtist(_:)` which sets `selectedSection = .artists` and scrolls the artist list), year, track count, and an accent-colored Play button. Tracks are grouped by disc with "Disc N" headers. Each row shows number, title, featured artist if different from album artist, and duration. A footer shows total track count and runtime. Back navigation calls `viewModel.clearBrowsingAlbum()`.

**Search:** `AppViewModel.searchText` is the single source of truth. `filteredAlbums()`, `filteredArtists()`, `albumsForArtistFiltered()`, and `allTracks()` all filter against it. Clearing `searchText` also clears `collapsedSearchOverrides`.

**Accent color pattern:** Both `AlbumDetailView` and `LibrarySidebar` compute a local `accent` color using `browsingAlbumAccentColorDark` / `browsingAlbumAccentColorLight` from `AppViewModel`, falling back to hardcoded defaults (`#7B5AA3` dark / `#9B74BA` light).

---

## Now Playing Screen

Full-screen overlay (`NowPlayingView.swift`) triggered by expanding the mini player. Sits in a `ZStack` in `ContentView` above the main split view, with a `.move(edge: .bottom).combined(with: .opacity)` transition.

**Layout (top to bottom):**
- Album cover (420×420 px) with drop shadow — `AlbumCoverView` inside a `ZStack` that also publishes the cover's center point via `CoverCenterKey` preference key (used to position the idle overlay cover)
- Metadata: track title (26pt semibold), artist – album (year) (17pt, 75% opacity)
- Scrubber (`ScrubberView`): `Slider` with hidden thumb, elapsed and total time labels in caption monospaced font
- Transport controls (`TransportControlsView`):
  - Previous / Play/Pause / Next buttons (22–30pt) with 64pt spacing
  - Volume row: speaker icons + `Slider` + Show/Hide Queue capsule button
- Up Next queue (`UpcomingListView`): all tracks in the current album, each row showing track number, title, artist, duration; waveform icon on the current track; disc headers for multi-disc albums; tapping a row calls `viewModel.play(album:trackIndex:)`. Toggled by `playback.isQueueVisible` via `viewModel.toggleQueueVisibility()`.

**Animated background (`NowPlayingBackground.swift` / `NowPlayingBackgroundRenderer.swift`):** Custom Metal shader pipeline — tiles and twirls the album artwork, runs through a dual Kawase blur pyramid (extra level on HiDPI), then a finalization pass applies saturation boost (1.4×), darkening, and film grain. Renders at 30 FPS. Parameters: speed 0.02, sample position multiplier 3.0, highlight cap 0.85 (light) / ~0.39 (night mode).

**Idle mode (`IdleManager`):** `@MainActor ObservableObject` owned by `ContentView`. Three-phase animation triggered after a configurable timeout:
1. Controls fade out (0.25 s `easeOut`)
2. Album cover shrinks to 88×88 px and springs to the bottom-left corner (spring response 0.55, damping 0.82) — implemented as a separate `IdleCoverView` overlay in `ContentView` so it's outside the `ScrollView` and unaffected by scroll position
3. Track title, artist, album text fades in (0.3 s `easeIn`)

Wakes on any `mouseMoved`, `leftMouseDown`, `rightMouseDown`, `keyDown`, or `scrollWheel` event. Wake animation: spring (response 0.45, damping 0.85) reverting all three phases simultaneously.

**Exit:** Back button in toolbar or Esc key (`onExitCommand`). Sets `viewModel.isNowPlayingExpanded = false` with spring animation.

---

## Mini Player Bar (`MiniPlayerBar.swift`)

Always-visible floating pill at the bottom of the window (24 pt below bottom edge, `zIndex` above everything except the Now Playing overlay).

- Previous, Play/Pause, Next buttons
- Album cover thumbnail (36×36 px)
- Track title and artist (truncated)
- Thin progress bar along the bottom edge of the pill
- `glassEffect` on macOS 26+, `ultraThinMaterial` fallback
- Tapping expands to Now Playing (sets `viewModel.isNowPlayingExpanded = true` with spring animation)

---

## Dynamic Color Theming

Driven by `AlbumColorExtractor` (`AlbumColorExtractor.swift`), called from `AppViewModel`.

- **Now Playing background color:** `vibrantColor(from:)` — area-average dominant color, used to seed the Metal background shader. Stored in `AppViewModel.backgroundColor`.
- **Accent colors:** `accentColors(from:)` — k-means clustering (k=4) on artwork downsampled to 60×60 px. Returns `(dark: Color, light: Color)` pair, each selected for vibrancy and WCAG contrast ≥3:1 against their respective backgrounds. Stored in `AppViewModel.browsingAlbumAccentColorDark/Light`, updated asynchronously on `selectBrowsingAlbum()`.
- **Text color:** `preferredTextColor(for:)` — WCAG luminance check selects white or near-black. Stored in `AppViewModel.foregroundColor`.
- **Night Mode:** `AppViewModel.isNightMode: Bool` persisted in `UserDefaults`. Applied via `.preferredColorScheme()` on `ContentView`.

---

## System Integration

**Now Playing Info Center (`NowPlayingController.swift`):** Publishes title, artist, album, duration, elapsed time, artwork, and playback state to `MPNowPlayingInfoCenter`. Updated on every play, seek, pause, and 0.5 s timer tick.

**Remote commands:** `MPRemoteCommandCenter` handles Play, Pause, Toggle Play/Pause, Next Track, Previous Track, and Change Playback Position — all wired to `AppViewModel` methods.

**Audio device monitoring:** CoreAudio `AudioObjectAddPropertyListener` on `kAudioHardwarePropertyDefaultOutputDevice`. On change, calls `AppViewModel.handleExternalPause()` which pauses playback and stops the listen tracker.

---

## Last.fm Scrobbling

**Authentication (`LastFMSessionController.swift`):**
- `startAuth()` — fetches a token, opens `last.fm/api/auth/?token=...` in the browser, sets status to "Authorize in browser, then click Complete Linking"
- `completeAuth()` — exchanges token for session key via `auth.getSession`, stores key in Keychain (`KeychainHelper`) and username in `UserDefaults`
- `unlink()` — removes session key from Keychain, clears username
- State published via `@Published var username: String?` and `@Published var status: String`, bound into `AppViewModel.lastFMUsername/lastFMStatus`

**Scrobbling rules (all must be met):**
- Track duration > 30 seconds
- Accumulated listening time ≥ min(50% of duration, 240 s)
- Valid session key present

Listening time is tracked by `ListenTracker` (private struct in `AppViewModel.swift`), which accumulates real wall-clock time between `start()`/`stop()` calls, excluding paused intervals and accounting for seeks.

**Data sent per scrobble:** artist, title, album, album artist, track number, duration, MusicBrainz IDs, Unix timestamp of track start

**Featured artist handling:** If track artist contains the album artist (e.g., "slowthai feat. Mura Masa" where album artist is "slowthai"), the scrobble uses the album artist as the artist field, matching Last.fm conventions.

**Now Playing updates:** `updateNowPlaying()` called on `LastFMClient` each time a new track starts.

**API auth:** MD5-signed form-encoded POST requests. API key/secret loaded from `LastFMSecrets.plist`.

---

## Settings (`SettingsView.swift`)

Opened via Cmd+, (standard macOS convention). Flat `VStack` layout with four sections:

| Setting | Detail |
|---|---|
| Library location | Shows current path (middle-truncated); Change button opens `NSOpenPanel` |
| Rescan | Re-scans using cache |
| Rescan & Clear Cache | Deletes cache, forces full re-scan |
| Night Mode | Toggle; stored in `UserDefaults` via `AppViewModel.isNightMode` |
| Idle timeout | Picker: Never / 5 s / 15 s / 30 s / 1 min; stored in `UserDefaults` via `AppViewModel.nowPlayingIdleTimeout` |
| Last.fm | Link / Complete Linking / Unlink buttons; shows linked username |

---

## Architecture Notes

- **`AppViewModel`** (`AppViewModel.swift`) — central `@MainActor ObservableObject`. Owns all services, holds all published state, coordinates between `PlayerController`, `NowPlayingController`, `ScrobbleService`, `LastFMClient`, and `AlbumColorExtractor`. Injected as `@EnvironmentObject`.
- **`PlaybackState`** — separate `@MainActor ObservableObject` for high-frequency playback properties (`isPlaying`, `position`, `duration`, `volume`, `isQueueVisible`). Owned by `AppViewModel`, injected as a second `@EnvironmentObject` to isolate re-renders.
- **`LibraryScanner`** — async, returns `[Album]`. Each `Album` contains `[Track]`. Caches results by folder signature.
- **`PlayerController`** — wraps `AVPlayer`. Callbacks: `onTrackEnd` and `onExternalPause`.
- **`ScrobbleService` / `LastFMClient`** — separated for testability; both use protocols so tests inject mocks.
