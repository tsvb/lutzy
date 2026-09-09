# LUTzy

A macOS app that applies `.cube` LUTs to RAW and other images. It can also build a LUT from a RAW + JPEG pair.

SwiftUI and Core Image. No third-party packages. Runs on macOS 14; you need Xcode 26 to compile it (see [Build](#build)).

## Features

- RAW is demosaiced with `CIRAWFilter`, not the embedded preview. DNG, CR2, CR3, NEF, ARW, ORF, RAF, RW2, PEF, SRW, X3F, RAW. Also JPEG, PNG, TIFF, BMP, HEIC.
- Drop a file or a folder on the window. `⌘O` opens a file, `⌘⇧I` imports from Photos (max 50), `⌘⌥I` opens a source folder.
- `.cube` 3D LUTs (`LUT_3D_SIZE`, `DOMAIN_MIN` / `DOMAIN_MAX`) go through `CIColorCubeWithColorSpace` on Metal. The sidebar scans a folder recursively, groups by subfolder, and is searchable. Intensity 0–100%.
- LUT folder and source folder are supposed to persist via security-scoped bookmarks. They don't — nothing is sandboxed yet. [Build](#build).
- `V` toggles side-by-side vs single view. Hold Space (single view) for the original. `↑` `↓` walk the library.
- `⌘I` is the inspector. **Info**: histogram of what's on screen (graded, or original while Space is down) plus EXIF / TIFF / GPS. **Develop**: the `CIRAWFilter` knobs this file's decoder actually supports. **Adjust**: nine sliders after develop and before the LUT (exposure, brightness, contrast, saturation, highlights, shadows, temperature, tint, vibrance).
- A source folder gets a filmstrip. `←` `→` or `[` `]` step through it; the current look stays on. `⌘R` rescans.
- Export is 16-bit TIFF, JPEG (quality 0.95), or PNG, always full resolution, named `{photo}_{LUT}.ext` (spaces in the LUT name become underscores). **Export All** (`⌘⇧E`) writes the whole look — develop, adjustments, LUT, intensity — and counts failures instead of aborting.

## Derive LUT from JPG

`File ▸ Derive LUT from JPG…` (`⌘D`). Pick the RAW, pick the JPEG, hit Derive. The JPEG is treated as a look (the manufacturer's color science, or whatever picture profile was on). LUTzy writes the difference against a neutral RAW develop.

The pair has to be the same frame — aspect within 1%. Pixel size can differ; that's normal.

```
  RAW  ──► CIRAWFilter (neutral baseline) ─┐
                                           ├─► align ─► sample smooth regions ─► 33³ cube ─► .cube
  JPEG ─► decode ─► edge mask ─────────────┘                                      │
                                                                                  └─► analysis report
```

The RAW is developed with the same default `CIRAWFilter` settings the rest of the app uses, so the LUT applies without a baseline mismatch. Both images are Lanczos-scaled onto a shared working extent (long edge capped at 3000 px; 200k samples don't get better from a 60 MP buffer) and aligned by luma cross-correlation. An edge mask on the JPEG keeps in-camera sharpening out of the color samples. Surviving pixels (~200k, from a 2M draw) fill a 33³ cube; empty cells are pulled from neighbors, then identity.

The LUT previews on whatever image you have open and stays in memory until **Save to LUT Folder…**.

The report is a tone curve (R/G/B vs identity) plus saturation, sharpening, coverage, sample count, alignment, and camera EXIF. Sharpening is measured, not applied — a cube can't sharpen, and there isn't a second stage that does.

## Shortcuts

| Key | Action |
|---|---|
| `↑` `↓` | previous / next LUT |
| `←` `→` or `[` `]` | previous / next image (when a set is loaded) |
| Space (hold) | original, in single view |
| `V` | side-by-side / single |
| `⌘I` | inspector |
| `⌘O` | open image |
| `⌘⇧I` | Photos |
| `⌘⌥I` | source folder |
| `⌘R` | rescan source folder |
| `⌘⇧L` | LUT folder |
| `⌘D` | derive |
| `⌘S` | export |
| `⌘⇧E` | export all |

Letter keys are a window-level `NSEvent` monitor. SwiftUI's `.onKeyPress` doesn't fire reliably inside `NavigationSplitView`. Command-keys go through the menu bar.

## Build

```bash
swift run           # launch
open Package.swift  # same binary, Xcode debugger
swift test
```

There is no `.xcodeproj`. Both of those Run paths produce a SwiftPM executable, not a `.app`. `Package.swift` excludes `Assets.xcassets` and `LUTzy.entitlements`; the appiconset is empty; there is no `Info.plist` or bundle identifier. `LUTzy.entitlements` is a real sandbox file (user-selected read/write, app-scoped bookmarks) sitting unused. Wiring that up is an Xcode app target, which this repo doesn't have.

**Run:** macOS 14. **Compile:** Xcode 26 / macOS 26 SDK. Deployment target and SDK are different things. The compiler will reject any API newer than 14 unless it's `#available`-guarded. Highlight recovery on `CIRAWFilter` (`isHighlightRecoveryEnabled` / `isHighlightRecoverySupported`) only exists in the 26 SDK, so an older Xcode can't build the package at all — `#available` does not conjure a missing symbol. The binary still runs on 14.

`swift test` generates fixtures into a temp directory. Tests that need a real RAW/JPEG pair look in `realworldtest/` (gitignored) and skip if it isn't there. Set `LUTZY_BENCH=1` for the preview-cost tests. CI is debug build → test → release build on `macos-26`.

Everything of substance is in `Sources/LUTzyKit`. `Sources/LUTzy` is `@main` and an AppDelegate that forces `.regular` activation, because a bare executable otherwise starts as a background process with no Dock icon. Only `ContentView` and `LUTzyCommands` are public, so the kit can be `@testable import`ed.

The look is an `EditDocument` (develop + adjustments + LUT). Preview, histogram, and both export paths render that document through one `RenderEngine` actor / one `CIContext`. The only difference between preview and export is scale: 1600×1200 vs full. `WorkingSpace` (sRGB) is used for both cube interpolation and encoding, so those two can't drift. Non-RAW files go through `ImageDecoder.orientedLoadOptions` because `CIImage(contentsOf:)` ignores EXIF orientation and `CIRAWFilter` doesn't.

Swift 6 language mode on every target. No `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.

Pipeline notes: [docs/PHASE2_SPEC.md](docs/PHASE2_SPEC.md). Standing review: [docs/CODE_REVIEW.md](docs/CODE_REVIEW.md).

## License

[MIT](LICENSE)
