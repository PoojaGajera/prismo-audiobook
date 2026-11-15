# Handoff: where the Audiobooks app stands

Summary of a long working session (14–15 Nov 2026), written so a new chat can pick up from here.
Read this together with `CLAUDE.md`, which has the architecture and conventions; this file
is the story so far, the current state, and what's open.

## Repo state (important)

- **Nothing from this session is committed.** `main` has only `03cb933 Initial commit`. All the
  work below is uncommitted changes plus untracked files (about 40 paths in `git status`).
  Committing early in the next chat is a good idea.
- Untracked folders you'll see: `TestAudio/` (test audiobooks I made with macOS text-to-speech, not
  git-ignored; delete them or add them to `.gitignore` before committing) and `Archive/Owl/` (see "Owl mascot").
- Another session (not this one) also changed the code in parallel: it built
  `App/Views/NowPlayingPanel.swift` (the mini bar and the full player as one dragging surface), the
  `ReactiveMascot` on the player cover, and the owl (since archived). Expect code here that this
  summary doesn't fully describe; check `CLAUDE.md` and the files themselves.

## Build and test setup

- Xcode 27 at `/Applications/Xcode.app`. `xcode-select` now points at Xcode, so plain `xcodebuild`
  works. (Earlier it pointed at Command Line Tools, and every command needed
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.)
- Simulator build used throughout:
  ```bash
  xcodebuild -project AudiobookPlayer.xcodeproj -scheme Audiobooks \
    -destination 'id=096FB963-8470-430C-98A9-0806B4D25FB3' -derivedDataPath <scratch>/dd \
    build CODE_SIGNING_ALLOWED=NO
  ```
  The simulator is the iPhone 18 Pro, `096FB963-8470-430C-98A9-0806B4D25FB3`. The bundle id is
  `com.pooja.books.audiobooks`. Install with `xcrun simctl install`, then `xcrun simctl launch`.
- Simulator tips learned the hard way:
  - Take screenshots with `xcrun simctl io <udid> screenshot`. The control tool's screenshots can
    lag one action behind.
  - The first tap on a new screen sometimes doesn't register.
  - For a mid-drag screenshot, run a delayed `simctl io screenshot` in the background, and hold
    the drag with `touch_path`.
  - The app data folder changes on reinstall, so re-run `xcrun simctl get_app_container … data`.
    The library is `Library/Application Support/Library/library.json`.
  - App settings (UserDefaults) are cached by iOS, so editing the plist file doesn't take effect.
    Change them through the UI or uninstall.
  - To put files in "On My iPhone", copy them into the simulator's
    `…/Containers/Shared/AppGroup/<group.com.apple.FileProvider.LocalStorage>/File Provider Storage/`.
    A file can also be imported with `xcrun simctl openurl <udid> file:///path`.
- **These only work on a real iPhone:** speech recognition (Find Chapters / chapter names), widgets,
  the system volume slider, Lock Screen controls, App Group sharing, background audio.

## What was built (feature by feature)

### Library (`App/Views/LibraryView.swift`)
- The home screen is just the books: no greeting, no "Continue listening" card, no "shelf" wording.
  The empty state says "No books yet".
- **Tiles and List layouts** (a toggle next to Settings, remembered in `@AppStorage("libraryLayout")`).
  Tiles reserve 2 title lines, 1 author line and 1 progress row, so rows line up; long titles
  end in "…". Finished books show a full bar and "Finished".
- **Card status line:** whole-book % plus time left in the **current chapter** ("42% · 12m left in
  chapter"). It shows "New" before starting, and "Finished" at the end.
- **Tapping a card** opens the player without auto-playing. Long-press: Play, Mark Finished,
  Start Over, **Edit Details…**, Delete.
- **Order:** most recently played first. Pressing Play moves a book to the top at once
  (`lastPlayed` is set in `play()`); merely opening a book doesn't.
- **Sync button** (and pull-to-refresh): folder sync, then a refresh of every book's details.
- Prism pattern background only on the splash; other screens use the plain page colour.

### Importing and the watched folder (`App/Library/FolderSync.swift`)
- Settings → Audiobooks Folder → **Choose Folder…** (or "Use My Audiobooks Folder" in the empty
  library). Any folder name works; it's remembered with a bookmark.
- It syncs on launch, on return to the app, and via Sync / pull-to-refresh.
  - Each top-level audio file is a book. Each subfolder of audio files is one book, titled after
    the subfolder.
- Duplicates are skipped by file name+size signature or by path. A book deleted in the app is not
  re-added. iCloud placeholders are downloaded and picked up next time.
- Every import path (+, Files, share sheet, folder) goes through `LibraryStore.importStaged`, which
  queues the chapter scan and the details lookup.

### Chapters
- `ChapterScanner`: automatically runs Find Chapters on imported books that have no chapter
  markers and are at least 2 minutes long. Progress shows on the card. It reports via
  `LibraryStore.post` (a queued alert, so messages don't overwrite each other). A failure reason
  is shown once per session.
- `ChapterDetector`:
  - Fixed to build on the iOS 27 SDK.
  - The `SpeechAnalyzer` path is gated to iOS 27; older systems use `SFSpeechRecognizer`.
  - "Recognizer completely failed" now throws `speechUnavailable` instead of reporting 0 chapters.
- **Spoken chapter names:** `chapterName` keeps a short title read after "Chapter N"
  (8 words or fewer, ending with a full stop or a pause), giving "Chapter 3: The Burrow". It's
  verified with sample transcripts on the Mac, **not yet on a device.**
- **Chapter titles from file names** follow the tidy book title (`LibraryStore.tidyChapterTitles`).
- On the simulator, speech recognition fails ("Failed to initialize recognizer"); that's expected.

### Book details (`BookMetadata.swift`, `MetadataEnricher.swift`, `BookDetailsView.swift`)
- **Title cleanup (`TitleCleaner`):**
  - Removes track numbers, "(Unabridged)", "[Opus 5.1ch Encode]" (any `[...]`/`{...}`),
    noise in parentheses, bitrates and file extensions.
  - Turns `_`, `.` and `-` separators into spaces, and capitalises all-lowercase names.
  - Keeps "1984", "11.22.63", "Catch-22", "(Monologues)".
- **Lookup (automatic after import, and on app open for unchecked books):**
  - Apple iTunes Search (audiobook listing) supplies genre, year and series.
  - **Covers are publisher covers only:** the Apple **ebook** listing in the default store (UK by
    default, set in Settings), falling back to Open Library print editions. Audiobook art with
    "Narrated by…" is never used.
  - **Descriptions are the physical book's blurb from Open Library** (like Goodreads), with
    footnotes removed. If there's none, the ebook text and then the audiobook text are used, with
    narration and ebook lines removed. Google Books isn't used: its keyless quota is often used up.
  - Open Library details are only trusted when the author is known.
  - `lookupVersion` (currently 4) forces one re-pass when lookups improve.
- **Edit Details** (long-press → Edit Details):
  - Fields: title, author, series, genre, year, publisher, and a scrollable description box.
    Labels sit above the values. There is no narrator field, by request.
  - **Change Cover…** shows only covers of the exact same book (exact title plus author), from
    every English Apple store plus English print editions. There are no region buttons; library
    rebinds and repeat photos are removed. **From Photos** is also available.
  - **Look Up Details Online…** lets you pick a match and use its details, its cover, or both.
  - Saving marks the book `detailsEdited`, so automatic lookups never touch it again.
    `coverOrigin` is "file", "publisher" or "user", and user-chosen covers are never replaced.
- Covers are shown **cropped to fill** (a "fit with blurred backdrop" style was tried and rejected).

### Player
- One panel (`NowPlayingPanel`, from the other session):
  - The mini bar is docked to the bottom with rounded top corners, 104 points tall.
  - **Dragging up** follows the finger. The cover grows into the full player, and **the title and
    author travel with it** (`TravellingTitle`, tied to the cover so they never overlap it).
  - Since this summary was first written, the open player has been made YouTube Music-style: a
    full-width cover with 8-point corners, the title and author left-aligned under it, no mascot,
    icon-only option buttons, and Apple's default font (SF Pro) app-wide instead of SF Rounded.
  - Tap or drag opens it; the chevron or a drag down closes it.
- Full player (`PlayerView`):
  - **Layout:** chevron (44 pt), then a **big cover** (full width less 24-point margins, shrinking
    only on short screens) with the mascot perched on it. Below that, the title and author, the
    chapter chip ("2 of 3 · Chapter 2: …", which opens the chapter list), and the progress bar.
  - **Progress bar times:** elapsed on the left. On the right, time left **in the chapter**; tap it
    to switch to **in book** (remembered).
  - **Controls:** previous chapter, skip back, play, skip forward, next chapter.
  - **Bottom bar:** speed, **one bookmark button**, and AirPlay.
- **Removed by request:** "NOW PLAYING", the settings gear, the volume row, the chapter-list
  button, speed in the middle of the progress row, and the "left in book" line.
- **Speed button → "Player Controls" sheet:**
  - Speed slider 0.5–4.0 (the cap was raised to 4×), −/+, and 1× / 1.25× / 1.5× presets.
  - Volume (the system slider; blank on the simulator).
  - **More** opens Settings scrolled to the playback section.
  - **Boost Volume was not built:** AVPlayer can't go above 1.0; it would need an AVAudioEngine
    rewrite.
- **Bookmark:** one tap saves it, then the alert "Your bookmark has been saved at …" offers
  Add note / See bookmarks / OK.
- **Spacing:** the 4-point scale `Spacing` (Shared/Theme.swift: 4, 8, 12, 16, 24, 32) is used in
  the player and mini bar. Gaps are small within groups and 24 between groups. Every button is at
  least 44 points.

### Settings
- Audiobooks Folder (choose, check now, change, stop watching).
- Book Details: default cover store (UK).
- Playback, Smart Rewind, Speed, and Progress ("Use chapter context", "Adjust times for speed";
  the two old remaining-time toggles were removed).
- Appearance (motion toggle).

### Widget
- The small widget shows a big cropped cover, play/pause on its corner, and the title. There's no
  progress bar. **Not checked on a device yet.**

## Open items / ideas not done

- **Owl mascot.** Another session built a full owl (8 moods and wired earphones), a Prism/Owl theme
  switcher and an owl app icon, then **archived it in `Archive/Owl/`** (see its README).
  The README points to commit `c47f906`, but **that commit doesn't exist in this repo** (only
  `03cb933`). So the theme-switcher wiring has to be rebuilt by hand: `Archive/Owl/` has only
  `Owl.swift`, `OwlShapes.swift`, the assets and the artwork. The user said "not now" to the owl.
- **Boost Volume** (needs an AVAudioEngine-based player).
- **Needs a real iPhone:** speech chapter detection and names, the widget redesign, Lock Screen,
  the volume slider in Player Controls.
- **Chapter scan limits:** the app must stay open (iOS suspends it in the background), and an
  interrupted scan isn't resumed after relaunch.
- **Folder sync limits:**
  - Books are **copied in**, so they take double storage. Playing them in place would be a bigger
    change.
  - Adding a file to an already-imported folder doesn't update that book.
- Lookups find no narrator (the field was removed by request anyway). A generic title with no
  author may not match; fix it with Look Up Details.

## Preferences the user has expressed

- Clean, uncluttered player and library; no extra labels.
- Publisher covers (not audiobook art), cropped to fill; descriptions about the book, not the
  narration.
- UK covers by default.
- A 4-point spacing grid and UX-law-minded layouts (proximity, 44-point targets).
- Smooth, finger-following gestures.
- Explanations in plain language. The user tests on their own iPhone.
