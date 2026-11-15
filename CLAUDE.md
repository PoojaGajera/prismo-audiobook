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
- `ChapterDetector` (App/Library): Find Chapters. (1) One sequential AVAssetReader pass per file, downmixed to 8 kHz mono float, giving a 100 ms RMS level track. An adaptive threshold (5th percentile + 30% of the gap to the 60th percentile) yields silences of 1.2s or more. (2) For the longest pauses (spaced 60s or more apart, at most 160), it reads 7s after each pause at 16 kHz and runs `SFSpeechRecognizer` on-device. `chapterTitle(from:)` accepts openings like "Chapter …", "Prologue", or "Part/Book + number". A short title read right after the number (`chapterName`: 8 words or fewer, ending with a full stop or a pause) becomes the chapter name, e.g. "Chapter 3: The Burrow". (3) Two or more spoken hits: use those. Otherwise: longest pauses spaced by `minChapterLength`. UI: `ChapterDetectionView`, results applied via `PlayerController.replaceChapters`, which keeps `Book.originalChapters` for restore. Needs `NSSpeechRecognitionUsageDescription` in App-Info.plist.
- `ChapterScanner` (App/Library): runs `ChapterDetector` automatically, one book at a time, on imported books with `chapterSource == .none` that are at least 2 min long. Progress shows on the library cards. Results go through `PlayerController.replaceChapters` for the loaded book, otherwise `LibraryStore.replaceChapters(of:)`. Outcomes are reported via `LibraryStore.post(_:)`, which queues alerts.
- `FolderSync` (App/Library): a watched folder picked once in Files (bookmark in UserDefaults). It syncs on launch, on return to foreground, and on pull-to-refresh. A top-level audio file is one book; a subfolder of audio files is one book. Files are copied in. A book is skipped when its file names and sizes match a library book, or when its path or signature is in `folder-sync.json`, so deleted books aren't re-added.
- Book details (`App/Library/BookMetadata.swift`, `MetadataEnricher.swift`, `App/Views/BookDetailsView.swift`):
  - `TitleCleaner` strips file-name noise such as track numbers, "(Unabridged)" and bitrates, and splits off "Series, Book N".
  - `MetadataLookup` searches Apple's iTunes Search API (`media=audiobook`). Each `CoverRegion` country store has its own editions/covers; the default is UK (`AppSettings.coverRegion`). Open Library is the fallback, used only when the author is already known.
  - `MetadataEnricher` runs once per book (`Book.detailsChecked`) after import and on app open. It retries when offline and never overwrites hand edits.
  - Covers are always publisher covers, never audiobook art (which often says "Narrated by …"). They come from Apple's **ebook** listings (`searchAppleEbooks`) and English Open Library print editions. `publisherCover` is used by automatic lookups; `coverOptions` feeds the picker.
  - The picker has no region UI. It keeps only the same book (`isSameBook`: exact `titleKey` plus author), and removes duplicate images, library rebinds and repeat photos of one publisher and year.
  - Descriptions are the physical book's blurb (as on Goodreads), from the Open Library work (`bookDescription`), with Markdown and source footnotes removed. If there's none, the ebook text is used, else the audiobook text; both have narration and ebook-only sentences removed (`withoutNarration`). Google Books isn't used because its keyless quota is shared and often used up. Bumping `MetadataEnricher.lookupVersion` gives already-checked books one more automatic pass.
  - `Book.coverOrigin` is "file", "publisher" or "user". Lookups replace file or audiobook art with the publisher cover, but never a cover the user chose.
  - The Library's Sync button and pull-to-refresh both call `LibraryView.syncAll`. It runs a folder sync, then `MetadataEnricher.refreshAll()`. That re-checks every book not edited by hand (`detailsEdited`), lets a confident match update genre, year, publisher, series and description, and keeps existing covers. Lookups are paced at about 0.7 s apart to stay under Apple's search rate limit.
  - Edit Details (long-press a card) saves through `LibraryStore.saveDetails`, which goes through `PlayerController.updateDetails` for the loaded book.
  - Replacing cover.jpg bumps `Book.coverVersion`, which keys `CoverCache`.
- `AppSettings`: global settings in `UserDefaults.standard` (app only). Anything the widget needs must be copied into `NowPlayingSnapshot`.
- Widget buttons use `AudioPlaybackIntent` intents from `Shared/PlaybackIntents.swift`, which iOS runs in the app process.
- Medium widget: a cover as tall as the widget, title, "Chapter N of M", progress, then previous chapter / skip back / play / skip forward / next chapter (`PreviousChapterIntent`, `NextChapterIntent`). Widgets can't animate, so the title can't scroll there; it ends in "…".
- Skip icons everywhere are `SkipGlyph` (Shared/Theme.swift): the plain `gobackward`/`goforward` circle at light weight with the seconds drawn as separate text, so the circle can grow without the number growing.

## Conventions

- SwiftUI + `ObservableObject`/`@Published` (not `@Observable`). Inject via `.environmentObject`. Sheets re-inject explicitly.
- Keep UI state in views; keep playback logic in `PlayerController`. When mutating the currently loaded book, go through `PlayerController` so its copy and the library stay in sync.
- Time formatting goes through `TimeFormat` (Shared).
- Spacing uses the 4-point scale in `Spacing` (Shared/Theme.swift: 4, 8, 12, 16, 24, 32): small steps inside a group, larger between groups, 24-point side margins, and buttons at least 44 points.
- The Library's big "Library" heading is drawn in the scroll content (24 pt below the bar buttons), not by the navigation bar, which is inline and shows a small title only after the heading scrolls away (`headingScrolledAway`). List view is one card per book, 12 pt apart; tiles are 24 pt apart.
- `NowPlayingPanel` is the mini bar and the full player as one surface. The open player is laid out like YouTube Music: a full-width cover (16-point margins, 8-point corners), then the title and author left-aligned under it. Mid-drag, the cover and the title (`TravellingTitle`) travel between the two layouts. The title is tied to the cover's frame (beside it, then under it, flush with its left edge), so it never crosses it. `PlayerView` reports the title's frame inside its margins.

## Now-playing panel (mini player ⇄ full player)

`App/Views/NowPlayingPanel.swift`, modelled on YouTube Music. The player is **not** a sheet. `LibraryView` overlays `NowPlayingPanel` on its NavigationStack and reserves `NowPlayingPanel.miniBarHeight` at the bottom via `safeAreaInset`.
- One surface, driven by `progress` (0 = mini bar, 1 = full). A drag anywhere on the panel follows the finger. On release, the projected end position (so flick speed counts) springs it open or closed. Taps on the mini bar, the chevron and `AppRouter.showPlayer` (book taps, widget URL) animate it the same way, and `showPlayer` stays in sync with it.
- `PanelChoreography` is `Animatable`, so springs pass through every intermediate layout. The mini controls fade out over 0–22% and the full player fades in over 50–100%. The background goes from frosted to the cover-tinted page, the corners flatten near the top, and the library dims behind.
- One travelling artwork: drawn by the panel, interpolated from the mini thumbnail rect (24, 24, 54×54) to the full player's placeholder. `PlayerView`'s artwork is an empty `Color.clear` that reports its frame in the `PlayerView.panelSpace` coordinate space via `onArtworkFrame`. If you change the mini bar's padding or thumbnail size, update `PanelChoreography.miniArtwork`.
- Child gestures win over the panel drag, so the scrubber still scrubs and buttons still tap.
- The open/close spring is sent with a marked transaction (`Transaction.isPanelMotion`), and `PanelChoreography` strips the animation from its children for it (`.transaction { if $0.isPanelMotion { $0.animation = nil } }`). The choreography is already interpolated frame by frame; letting children animate too made text and controls lag and smear (stutter). Keep this when adding things to the panel.
- `TravellingTitle` never re-lays-out text at in-between font sizes: it draws the mini bar's labels (subheadline semibold / caption) and the player's labels (title2 bold / body) at their real sizes, scales them together with `scaleEffect`, and cross-fades. It stands in for the real labels whenever 0.002 < progress < 0.998, so the swap only happens at rest, where the two are identical. (Swapping at 3%/97% made the title jump, because the cover still had 3% of its travel left.)
- Text that moves or resizes with the panel (mini bar, travelling title, player author) uses `FadedLineText`: it fades out at the end instead of "…", which otherwise jumps a letter at a time as widths change. `MarqueeText` looks identical at rest, so they swap without a jump.
- On release, the spring starts at the finger's speed (`DragGesture` velocity, relative to the distance left) and has no bounce (`interpolatingSpring(duration: 0.42, bounce: 0, initialVelocity:)`). Starting from rest made swipe-to-close stall and then move again (a visible double animation at the bottom).

### Player colours, chips and sheets (cover-driven, solid, no glass)
- **Colours come from the cover.** `CoverPalette.theme(for:)` (App/Views/Design.swift) finds the cover's dominant vivid hue (a weighted hue histogram, not the muddy average) and builds a light, airy `CoverTheme` (the user dislikes muddy/dark tones): `accent` (a clear colour for the play button, progress fill, selected chips), `deep`/`mid`/`light` (the background gradient: soft pastel → near white), `chip`/`onChip` (solid chip fills and their icons) and `sheet` (sheet background). All adapt to dark mode; grey covers get a neutral slate. It's passed down as `@Environment(\.coverTheme)`. The player no longer uses the blue `Theme.accent` or the iridescent ribbon (`PearlSlider` and `IridescentBar` take a `tint`).
- **Background:** a soft pastel of the cover colour at the top → near white from just above the bottom of the cover (light mode); cover tint → near-black in dark mode.
- **Spacing knobs:** `PlayerView.Gap` (top of App/Views/PlayerView.swift): `chapterToProgress`, `progressToControls`, `controlsToOptions`.
- **Option chips:** Speed, Bookmark, Chapters, More (the sleep timer was removed at the user's request). Solid `chip` capsules, 64 × 36 pt with a 44 pt tall tap area, 12 pt apart and centred as a group. **More** opens a sheet with Edit Details, Bookmarks and Playback Settings.
- **Sheets** (App/Views/PlayerSheets.swift): `SpeedSheet`, `MoreSheet`, `BookmarkSavedSheet` all use `PlayerSheetScaffold` (small round close button, centred title, solid `theme.sheet` background; it measures its content and sets the detent to fit, so there's no empty space at the bottom) and the same `SheetButton` / `ChipIconButton` pieces. Keep any new player sheet on this scaffold. Bookmarks: a tap saves it and opens `BookmarkSavedSheet` (optional note, See Bookmarks, Done) instead of alerts.
- **Long titles scroll:** the player's title and chapter name use `MarqueeText` (Design.swift), which scrolls only when the text doesn't fit, pauses at the start, holds still with Reduce Motion, and only runs while the player is fully open (`PlayerView.isActive`).
- **Speed buttons:** the speed sheet's quick buttons come from `AppSettings.speedButtons` (default 1×, 1.25×, 1.5×; 1–5 picked from `speedPresets`), set in Settings → Playback Speed → Speed buttons (`SpeedButtonsSettingsView`).
- `PlayBadge` draws the play triangle with no extra offset: the SF Symbol is already optically centred (a 3.5% nudge looked off-centre).

## Mascot

- `MascotView(size:mood:headphones:headphonesProgress:animated:)` (Shared/Mascot.swift) is the blue scalloped-badge mascot (`BadgeMascotView`). It stays still when `Theme.motionEnabled` is false (the Settings toggle) or Reduce Motion is on.
- Moods are `MascotMood`: `.happy`, `.listening`, `.curious`, `.excited`, `.sleepy`, `.sad`, `.wink`, `.surprised`.
- `ReactiveMascot` (App/Views/Design.swift): a base mood that pulls a random face when tapped, and winks when `reactTo` changes. It's used in the empty library (it was removed from the player cover at the user's request).
- Find Chapters moods: setup `.happy`, running `.listening`, found `.excited`, none found `.sad`, error `.surprised`. The splash winks before dissolving.
- The play/pause button is `PlayBadge` (Shared/Theme.swift), a plain accent circle used by both `BadgePlayButton` and the widget.
- **Archived:** the Owl mascot and the Prism/Owl theme switcher are in `Archive/Owl/`. That folder isn't built; see its README and git commit `c47f906` to restore them.

## Visual design ("prism")

- **Light / dark setting:** Settings → Appearance → Theme (Automatic / Light / Dark), stored as `AppSettings.appearance` (`AppAppearance`). `applyAppearance()` sets `overrideUserInterfaceStyle` on every window (so sheets and UIKit controls follow), on launch, on becoming active and when changed (with a cross-fade). All colours are dynamic, so nothing else needs to know.

Built around the mascot (`Shared/Mascot.swift`): sky blue `#078EFB`, pearl `#EEF4F9`, blush pink `#FB07CE`, ink `#0B1530`. All colours come from `Shared/Theme.swift`; don't use raw colours.
- Semantic tokens: `Theme.accent` (blue), `Theme.blush` (pink, used sparingly), `Theme.lilac`, `Theme.background`, `Theme.surface`, `Theme.hairline`, `Theme.onAccent`. `Theme.iridescent` is the cyan → blue → lilac → pink gradient used for progress.
- Type is Apple's default font (SF Pro) everywhere; don't add `design: .rounded`. `Theme.title(_:)` is just a weighted system style.
- "Prism" image asset (light and dark variants, in both app and widget catalogs) is the refracted glass pattern, rendered offline. `PrismImage` shows it. `PrismBackground(style: .header / .full / .splash)` adds drift and hue shimmer, gated by `AppSettings.backgroundMotionEnabled` and Reduce Motion.
- `App/Views/Design.swift`: `PrismBackground`, `ShimmeringPrism`, `PearlSlider` (scrubber), `IridescentBar`, `BadgePlayButton` (play button in the mascot's scalloped badge shape), `GlassIconButton`, `CoverPalette`. `View.glassCard()` is in Theme.swift.
- Mascot: `MascotView(size:mood:headphones:headphonesProgress:animated:)` with moods `.happy`, `.listening`, `.curious`. It blinks, glances around and bobs (TimelineView), and is still when `animated: false` or under Reduce Motion. Shapes in `Shared/MascotShapes.swift` are generated from the original SVG (1000×1000 artboard, normalised). Used in: splash, library header, empty library, importing overlay, cover placeholders, Find Chapters, widget empty state and placeholders.
- `App/Views/SplashView.swift`: the launch animation (pattern fades in, mascot pops in, headphones drop on, title appears, dissolve). The system launch screen is just the `LaunchBackground` colour (`UILaunchScreen` in App-Info.plist; generation turned off in build settings).
- App icon: mascot with headphones on the light prism pattern (`AppIcon.png`), plus a dark-mode variant on the dimmed dark prism (`AppIcon-Dark.png`, the `luminosity: dark` entry), shown when the Home Screen icons are set to Dark. The dark one was rendered on the Mac by compiling `Shared/Mascot.swift` + `MascotShapes.swift` with a small shim (Theme colours, `Color(hex:)`) and `ImageRenderer`, mascot size 880 on a 1024 canvas.

## Testing on device

Widgets, background audio, Lock Screen controls and App Group sharing need a real iPhone. The simulator is fine for UI and import/chapter parsing. A good test set is an M4B with chapters, an MP3 with ID3 CHAP frames, a plain MP3, and a folder of numbered MP3s.
