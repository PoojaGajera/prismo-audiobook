# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

A native iOS audiobook player: SwiftUI app + WidgetKit extension. iOS 18+, Swift 5 language mode, no third-party dependencies. See README.md for the feature list and install steps.

## Build & run

There is no Swift Package or CLI build. It is an Xcode project.

```bash
# List schemes / build for the simulator (Xcode creates schemes automatically on first open)
xcodebuild -project AudiobookPlayer.xcodeproj -list
xcodebuild -project AudiobookPlayer.xcodeproj -scheme Audiobooks \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Signing settings live in `Config/Config.xcconfig` (`BUNDLE_ID_PREFIX`, `DEVELOPMENT_TEAM`). `APP_GROUP_ID` is derived from them and expanded into both Info.plists and both entitlements files. Don't hard-code bundle IDs or the app group anywhere else.

## Project structure rules

- The project uses **Xcode 16 synchronized folders** (`PBXFileSystemSynchronizedRootGroup`):
  - `App/` → app target only
  - `Widget/` → widget extension only
  - `Shared/` → **both** targets
  Adding or removing a `.swift` file in these folders needs **no** `project.pbxproj` edit. Avoid hand-editing `project.pbxproj`.
- `Config/` is not a synced folder: Info.plists and entitlements are referenced by build settings only. Don't move them into a synced folder, or they'd be copied as resources and break the build.
- The app target defines the compilation condition `MAIN_APP`. Code in `Shared/` that touches app-only types (e.g. `PlayerController`) must be wrapped in `#if MAIN_APP`.

## Architecture

- `LibraryStore` (singleton, `@MainActor`, `ObservableObject`): the list of `Book`s, persisted as JSON at `Application Support/Library/library.json`. Audio lives in `Application Support/Library/Books/<uuid>/`, with an optional `cover.jpg`.
- `BookAnalyzer`: reads duration, tags, artwork and chapters. Chapters come from AVFoundation first, then `ID3ChapterParser` for MP3 `CHAP` frames, then are normalized to cover the file end-to-end. `assemble` joins several files into one global timeline.
- `PlayerController` (singleton, `@MainActor`): owns a single `AVPlayer`. A book can span several files; **all positions are global book seconds**. `Book.location(for:)` maps a global time to `(track, local)`. Track switching happens in `setTrack`, with seeks deferred via `pendingSeek` until the item is `readyToPlay`.
  - Smart rewind: `SmartRewind.amount(pausedFor:limit:)`, applied in `play()` using `pausedAt`, which persists via `book.lastPlayed`.
  - Saves position every 5s while playing, plus on pause, seek, and when the scene goes inactive.
  - Publishes Now Playing info and handles `MPRemoteCommandCenter`. With "Use chapter context" on, the Lock Screen scrubber shows the current chapter.
  - `updateWidget(reload:)` writes a `NowPlayingSnapshot` to App Group defaults, then reloads the widget and control.
- `AppSettings`: global settings in `UserDefaults.standard` (app only). Anything the widget needs must be copied into `NowPlayingSnapshot`.
- Widget buttons use `AudioPlaybackIntent` intents from `Shared/PlaybackIntents.swift`, which iOS runs in the app process.

## Conventions

- SwiftUI + `ObservableObject`/`@Published` (not `@Observable`). Inject via `.environmentObject`. Sheets re-inject explicitly.
- Keep UI state in views; keep playback logic in `PlayerController`. When mutating the currently loaded book, go through `PlayerController` so its copy and the library stay in sync.
- Time formatting goes through `TimeFormat` (Shared). Accent color: orange.

## Testing on device

Widgets, background audio, Lock Screen controls and App Group sharing need a real iPhone. The simulator is fine for UI and import/chapter parsing. A good test set is an M4B with chapters, an MP3 with ID3 CHAP frames, a plain MP3, and a folder of numbered MP3s.
