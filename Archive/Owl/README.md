# Archived: Owl mascot and the Prism/Owl theme switcher

Archived on 15 Nov 2026. Nothing in this folder is part of the build: it sits outside the synced `App/`, `Shared/` and `Widget/` folders.

## What's here

- `Owl.swift`: `OwlView`, the live-rigged owl. It has 8 moods (happy, listening, curious, excited, sleepy, sad, wink, surprised), eased transitions, blinks, head-bob, floating notes, z's and sparkles, and wired earphones with swaying cables.
- `OwlShapes.swift`: owl body parts generated from the original SVG (1000×1000 artboard, normalised).
- `Assets/App/PrismOwl.imageset`, `Assets/Widget/PrismOwl.imageset`: the refracted glass pattern in owl colours, light and dark.
- `Assets/App/AppIcon-Owl.appiconset`: the owl app icon (owl with earphones on the owl pattern).
- `Art/owl.svg` is the original artwork. `Art/owl-expressions.png` is a sheet of every expression.

## Bringing it back

The full working version, including the theme switcher in Settings, live theme switching, the widget following the theme, the alternate app icon and the owl perched on the player cover, is git commit `c47f906` ("Owl mascot with expressions and wired earphones; Prism/Owl theme switcher"), plus the init-order fix in `AppSettings` that came after it.

To restore it:
1. Move `Owl.swift` and `OwlShapes.swift` back to `Shared/`.
2. Move the imagesets back into `App/Assets.xcassets` and `Widget/Assets.xcassets`.
3. Bring back the theme system from `c47f906`. That means `AppTheme`, `Palette.owl` and `Theme.current` in `Shared/Theme.swift`; `MascotView`'s theme switch; `AppSettings.theme` and `matchAppIcon`; the Settings theme cards; and `.id(settings.theme)` in the library and player.
4. Add `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "AppIcon-Owl";` back to the app target's build settings.
