# LUTzy

A native macOS app for applying `.cube` 3D LUTs to RAW/DNG and standard images, and for deriving a reusable `.cube` from a RAW + JPEG pair.

Built with SwiftUI and Core Image. No third-party dependencies.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![UI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20Core%20Image-9cf)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)

## Features

**Open**

- Native RAW demosaic via `CIRAWFilter` — not the embedded JPEG preview.
- RAW: `DNG`, `CR2`, `CR3`, `NEF`, `ARW`, `ORF`, `RAF`, `RW2`, `PEF`, `SRW`, `X3F`, `RAW`.
- Standard: `JPEG`, `PNG`, `TIFF`, `BMP`, `HEIC`.
- Drag and drop a file or a folder onto the window. Import from Photos (up to 50 at a time) or open a folder from the toolbar.

**Grade**

- Standard `.cube` 3D LUTs (`LUT_3D_SIZE`, `DOMAIN_MIN` / `DOMAIN_MAX`), applied through `CIColorCubeWithColorSpace` on Metal.
- Sidebar library scans a folder recursively, groups looks by subfolder, and filters by name.
- Intensity slider (0–100%) blends the graded result back toward the original.

**Compare**

- Side-by-side original vs graded, or a single view — toggle with `V`.
- Hold `Space` in single view to flash the original.
- `↑` / `↓` steps through the library with a live preview.

**Inspect** (`⌘I`)

- **Info** — RGB / luma histogram of what is on screen (the graded result, or the original while `Space` is held), plus EXIF, TIFF, and GPS.
- **Develop** — `CIRAWFilter` controls for RAW files (exposure, boost, contrast, detail, sharpness, noise reduction, white balance, and others). Each control is shown only if that file’s decoder reports it as supported.
- **Adjust** — nine tone and color controls (exposure, brightness, contrast, saturation, highlights, shadows, temperature, tint, vibrance), applied after develop and before the LUT.

**Batch**

- Open a source folder (`⌘⌥I`) to scan recursively, grouped by subfolder. `⌘R` rescans.
- Filmstrip along the bottom; `←` / `→` (or `[` / `]`) steps through the set with the current look still applied.

**Export**

- 16-bit TIFF, JPEG (quality 0.95), or PNG, always at full source resolution — never the preview scale.
- Files are named `{photo}_{LUT}.{ext}`, with spaces in the LUT name replaced by underscores.
- **Export All** (`⌘⇧E`) writes the current look — develop, adjustments, LUT, and intensity — to every image in the set. Failures are counted and skipped; the run does not abort.

## Derive a LUT from a JPEG

In addition to applying LUTs, LUTzy can derive one from a matched RAW + JPEG pair.

The JPEG the camera wrote alongside the RAW is a look — the manufacturer’s color science, or whatever film simulation / picture profile was set. LUTzy compares a neutral RAW develop against that JPEG and writes the difference as a portable `.cube`.

**File ▸ Derive LUT from JPG…** (`⌘D`) — pick the RAW, pick the JPEG, then Derive.

```
  RAW  ──► CIRAWFilter (neutral baseline) ─┐
                                           ├─► align ─► sample smooth regions ─► 33³ cube ─► .cube
  JPEG ─► decode ─► edge mask ─────────────┘                                      │
                                                                                  └─► analysis report
```

1. The RAW is developed with the same default `CIRAWFilter` pipeline used everywhere else in the app, so the derived LUT applies without a baseline mismatch.
2. The pair is rejected if the aspect ratios differ (within 1%). Differing pixel dimensions are fine. Both images are Lanczos-scaled onto a shared working extent, capped at 3,000 px on the long edge, then aligned by luma cross-correlation.
3. An edge mask is built from the JPEG so in-camera sharpening does not contaminate the samples. About 200,000 samples are taken from smooth regions only.
4. Samples accumulate into a 33³ cube. Sparse cells are filled from their neighbors; anything still empty is anchored to identity.

The result previews on the current image immediately and stays in memory until **Save to LUT Folder…**, at which point it joins the sidebar like any other `.cube`.

### Analysis report

Each derivation includes a report (Swift Charts) describing what the look actually does:

| Metric | Meaning |
|---|---|
| **Tone curve** | Per-channel R/G/B input→output mapping, against the identity line |
| **Saturation** | Chroma ratio in smooth regions — `>1` more saturated, `<1` more muted |
| **Sharpening** | High-frequency energy ratio on the same pixels. Measured only — a LUT cannot sharpen, and LUTzy does not apply a separate sharpening stage |
| **Coverage** | Percentage of cube cells filled by real samples versus interpolated |
| **Samples** | Smooth-region pixels that survived the edge mask |
| **Alignment** | Integer-pixel shift between the JPEG and the neutral render (usually near zero) |
| **Camera** | Make / model and EXIF contrast, saturation, sharpness, and white-balance tags from the JPEG |

## Keyboard shortcuts

| Key | Action |
|---|---|
| `↑` / `↓` | Previous / next LUT |
| `←` / `→` (or `[` / `]`) | Previous / next image (when a set is loaded) |
| `Space` (hold) | Show original (single view) |
| `V` | Toggle side-by-side / single view |
| `⌘I` | Toggle inspector (Info, Develop, Adjust) |
| `⌘O` | Open image |
| `⌘⇧I` | Import from Photos |
| `⌘⌥I` | Open source folder |
| `⌘R` | Rescan source folder |
| `⌘⇧L` | Choose LUT folder |
| `⌘D` | Derive LUT from JPEG |
| `⌘S` | Export |
| `⌘⇧E` | Export All |

Arrow and letter keys are handled at the window level so they still work inside the split view. Command shortcuts go through the menu bar.

## Requirements

| | |
|---|---|
| **To run** | macOS 14.0 or later |
| **To build** | Xcode 26 or later (macOS 26 SDK) |

The deployment target is macOS 14; CI and local builds use the current SDK. Anything newer than 14 must be `#available`-guarded or it will not compile.

One RAW develop control — `CIRAWFilter` highlight recovery — exists only in the macOS 26 SDK, so an older Xcode cannot compile the package. The binary still runs on macOS 14.

## Build and run

LUTzy is a Swift package. There is no `.xcodeproj` in the repo.

```bash
swift run          # build and launch
open Package.swift # or: xed .  — then run the LUTzy scheme
swift test         # XCTest
```

`swift test` generates its fixtures at runtime; there is nothing to download. Tests that need a real RAW/JPEG pair look in `realworldtest/` (untracked) and skip when it is absent. Preview-cost benchmarks are gated on `LUTZY_BENCH`.

CI on every push and pull request: debug build → tests → release build, on a `macos-26` runner, still deploying to macOS 14.

### Packaging

Both `swift run` and Run from `Package.swift` produce a SwiftPM executable, not a bundled `.app`. `Package.swift` excludes `Assets.xcassets` and `LUTzy.entitlements`; the app-icon set is empty; there is no `Info.plist` or bundle identifier.

The entitlements file is valid (App Sandbox, user-selected file access, app-scoped bookmarks), but nothing applies it. Folder choices therefore do not survive a restart. A sandboxed app — including anything that could go to the App Store — needs an Xcode app target that does not exist yet, plus a 1024×1024 icon and a bundle identifier.

## Repository layout

The app is split so its own code can be unit-tested (`@testable` cannot import an executable target). Only `ContentView` and `LUTzyCommands` are public.

```
Sources/LUTzy/          @main entry point, AppDelegate, asset catalog (excluded from the target)
Sources/LUTzyKit/       models, view models, views
Tests/LUTzyKitTests/    XCTest; fixtures generated into a temp directory
docs/                   pipeline spec and standing review notes
```

## Architecture

- **One document, one pipeline.** [`EditDocument`](Sources/LUTzyKit/Models/EditDocument.swift) is the look: RAW develop, adjustments, LUT, and intensity. Preview, histogram, and both export paths render that document through the same graph; they differ only by [`RenderScale`](Sources/LUTzyKit/Models/RenderScale.swift) (preview is capped at 1600×1200; export is always full resolution).
- **One GPU context.** [`RenderEngine`](Sources/LUTzyKit/Models/RenderEngine.swift) is an actor and owns the only `CIContext` on the render path. `CIImage` / `CIFilter` stay inside it; `Sendable` values cross the boundary.
- **One color space.** [`WorkingSpace`](Sources/LUTzyKit/Models/WorkingSpace.swift) is the source of truth for LUT interpolation and output encoding (sRGB today). Cube data is laid out R-fastest → G → B, matching the `.cube` spec and Core Image.
- **Upright images.** `CIRAWFilter` honors EXIF orientation; `CIImage(contentsOf:)` does not, so every non-RAW decode goes through `ImageDecoder.orientedLoadOptions`. Preview, thumbnails, reported dimensions, and export agree.
- **Panels are a test seam.** Operations that need a file dialog split into a `perform…` core that takes a URL and a thin `…Dialog` wrapper. `NSOpenPanel` / `NSSavePanel` cannot run headless; that split is what makes export and save testable.
- **Work stays off the main actor.** Decode, preview rasterization, folder scans, LUT parsing, export, and derive run in the background and publish back to `@MainActor`. The intensity slider is debounced so a drag does not enqueue a render per tick.
- **Swift 6 language mode** on every target, with no concurrency escape hatches. Apple frameworks only: SwiftUI, Core Image, AppKit, PhotosUI, Swift Charts, ImageIO, Metal, simd.

Further reading: [docs/PHASE2_SPEC.md](docs/PHASE2_SPEC.md) (render pipeline and RAW develop), [docs/CODE_REVIEW.md](docs/CODE_REVIEW.md) (standing findings).

## License

[MIT](LICENSE).
