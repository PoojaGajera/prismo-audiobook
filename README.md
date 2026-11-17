# Prismo — an iPhone audiobook player

A native SwiftUI audiobook player for iOS 18+ with a Home Screen / Lock Screen widget and a Control Center play/pause control.

## Features

- **Import** MP3, M4B, M4A, AAC and MP4 audio from the Files app (or "Open in…" from other apps).
  Pick several files at once and choose **one book (each file is a chapter)** or **separate books**.
- **Automatic chapter detection**
  - M4B / M4A / MP4 chapter tracks (via AVFoundation)
  - MP3 ID3v2.3/2.4 `CHAP` frames (custom parser, `ID3ChapterParser.swift`)
  - Multi-file books: one chapter per file, with natural sort order (`Part 2` before `Part 10`)
- **Find Chapters** for books without any: transcribes the book on the device and adds a chapter wherever the narrator announces one ("Chapter one", "Chapter 12"…). Shows a preview first, and can be redone or restored.
- **Player:** play/pause, skip back/forward, previous/next chapter, scrubbing, speed 0.5×–3× (presets plus fine slider), system volume slider, AirPlay/Bluetooth output picker
- **Bookmarks** with optional notes (add, edit, delete, jump)
- **Resume where you left off.** Position is saved every 5 seconds, on pause, and when the app goes to the background.
- **Table of contents** with the current chapter highlighted and per-chapter durations
- **Global settings**
  - Skip intervals (5–90s, back and forward set separately)
  - Smart rewind on/off plus a rewind limit (rewinds more after longer pauses)
  - Use chapter context: the progress bar, labels and Lock Screen scrubber cover the current chapter
  - Show remaining time (−12:34) or the total length
  - Show total remaining time ("5h 12m left in book")
  - Adjust remaining times for playback speed
  - Default speed, and whether to remember the speed for each book
- **Lock Screen / Control Center / headphones / CarPlay** controls via `MPRemoteCommandCenter`
- **Widgets:** small and medium Home Screen widgets, plus Lock Screen circular, rectangular and inline widgets with **interactive play/pause and skip buttons**
- **Control Center control** (iOS 18), which can also go on the Lock Screen or the Action Button
- **Design:** an animated mascot, a refracted "prism" glass background that shimmers gently, rounded type, and light and dark looks. Animations can be turned off in Settings, and they respect Reduce Motion.

## Requirements

- A Mac with **Xcode 16 or later**
- An iPhone on **iOS 18 or later**
- An Apple ID. A free account works, but the app expires after 7 days and you re-run it from Xcode. A paid developer account ($99/yr) lasts a year.

## Install on your iPhone

1. Open `Config/Config.xcconfig` and set:
   - `BUNDLE_ID_PREFIX`: something unique, e.g. `com.yourname`
   - `DEVELOPMENT_TEAM`: your Team ID. You can also leave it empty and choose your team under **Signing & Capabilities** for both targets.
2. Open `AudiobookPlayer.xcodeproj` in Xcode.
3. If Xcode isn't signed in, add your Apple ID: **Xcode › Settings › Accounts**.
4. Plug in your iPhone and select it as the run destination.
   - First time only: turn on **Settings › Privacy & Security › Developer Mode** on the iPhone.
5. Press **Run** (⌘R).
   - First time only, on a free account: on the iPhone go to **Settings › General › VPN & Device Management** and trust your developer certificate.
6. Add the widget: long-press the Home Screen › **Edit › Add Widget › Prismo**.
   For Control Center: swipe down › **+ › Add a Control › Prismo**.

> **App Groups:** the app and the widget share playback state through an App Group (`group.<BUNDLE_ID_PREFIX>.audiobooks`). With automatic signing, Xcode registers it for you. If you see a signing error about App Groups, open **Signing & Capabilities** on each target and click the refresh/"Try Again" button.

## Project layout

```
AudiobookPlayer.xcodeproj   Xcode project (folders are synced, so new files are picked up automatically)
App/                        App target
  AudiobookApp.swift        Entry point, URL handling
  Models/                   Book, Chapter, Bookmark, AppSettings, SmartRewind
  Library/                  LibraryStore (import + persistence), BookAnalyzer, ID3ChapterParser
  Player/PlayerController   AVPlayer engine, multi-file timeline, Now Playing, remote commands, widget sync
  Views/                    Library, Player, Chapters (TOC), Bookmarks, Settings, Speed
Widget/                     Widget extension (Home/Lock Screen widget, Control Center control)
Shared/                     Compiled into BOTH targets: shared snapshot store and App Intents
Config/                     xcconfig, Info.plists, entitlements
```

## How the widget controls playback

Widget buttons use App Intents that conform to `AudioPlaybackIntent` (`Shared/PlaybackIntents.swift`). iOS runs these intents **in the app's process**, launching it in the background if needed, so they can start and stop real audio. The intent bodies are wrapped in `#if MAIN_APP`, a compilation flag defined only for the app target, because the widget extension can't reach the player.

The app writes a `NowPlayingSnapshot` to the shared App Group defaults on every state change and reloads the widget timelines. While a book is playing, the widget extrapolates progress minute by minute.
