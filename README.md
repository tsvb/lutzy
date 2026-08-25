<div align="center">

# 🎨 LUTzy

### Color-grade RAW photos with `.cube` LUTs — and reverse-engineer a camera's look back *into* one.

A fast, native macOS app for applying 3D LUTs to RAW/DNG and standard images, with live side-by-side preview and a one-of-a-kind tool that **derives a LUT from a RAW + JPEG pair**.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![UI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20Core%20Image-9cf)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)
![GPU](https://img.shields.io/badge/rendering-Metal--accelerated-success)

</div>

---

## What is LUTzy?

LUTzy is a focused color tool built entirely on Apple frameworks — **SwiftUI** for the interface, **Core Image** (Metal-backed) for every pixel operation, and **zero third-party dependencies**. It does three things exceptionally well:

1. **Opens your photos** — native RAW/DNG demosaicing plus all the usual formats.
2. **Grades them with `.cube` LUTs** — browse a whole folder of looks and preview them instantly on the GPU.
3. **Reverses the process** — point it at a RAW file *and* the camera's straight-out-of-camera JPEG, and it will **synthesize a `.cube` LUT** that turns the neutral RAW into that JPEG's look. Bottle your camera's color science (or a borrowed film simulation) and apply it to everything else.

> [!TIP]
> The headline trick lives in **[Derive a LUT from a JPG](#-derive-a-lut-from-a-jpg)**. If you've ever wanted to capture a camera's JPEG look as a reusable LUT, that's the section to read.

---

## ✨ Features

### Open anything
- **Native RAW/DNG** via Core Image's `CIRAWFilter` — proper demosaicing, not just the embedded preview.
- Supported RAW: `DNG`, `CR2`, `CR3`, `NEF`, `ARW`, `ORF`, `RAF`, `RW2`, `PEF`, `SRW`, `X3F`, `RAW`.
- Standard formats: `JPEG`, `PNG`, `TIFF`, `BMP`, `HEIC`.
- **Drag & drop** a single image *or* a whole folder onto the window.
- **Import from Photos** (up to 50 at once) or **import a folder** straight from the toolbar.

### Grade with LUTs
- Parses standard `.cube` 3D LUTs (`LUT_3D_SIZE`, `DOMAIN_MIN`/`MAX`) and applies them through `CIColorCubeWithColorSpace` — **fully GPU-accelerated** via Metal.
- **Sidebar library** scans your LUT folder recursively and groups looks by subfolder, with a live search field and a running count.
- **Folder access survives restarts** through App Sandbox security-scoped bookmarks — pick your LUT folder once.

### Compare like you mean it
- **Side-by-side** original vs. graded, or a single full-bleed view — toggle with **`V`**.
- **Hold `Space`** to flash back to the original in single view.
- **`↑` / `↓`** cycles through every LUT in your library with instant preview.
- **Intensity slider** (0–100%) blends the graded result back toward the original, so a look can be dialled in rather than taken whole.

### Inspect what you're looking at
- **Info inspector** (**`⌘I`**): live RGB / luma histogram of the displayed image — the graded result, or the original while you hold `Space` — plus the file's EXIF, TIFF, and GPS metadata.

### Work in batches
- Point LUTzy at a **source folder** (**`⌘⌥I`**) and it scans recursively, groups by subfolder, and remembers the choice across launches. **`⌘R`** re-scans.
- A **filmstrip** appears along the bottom, with async-generated thumbnails.
- **`←` / `→`** (or **`[` / `]`**) step through the set; the selected LUT stays applied as you go.

### Export at full quality
- **16-bit TIFF**, **JPEG** (q 0.95), or **PNG** — always at full source resolution, never the downscaled preview.
- Output is auto-named `‹photo›_‹LUT name›.‹ext›`.
- **Export All** (**`⌘⇧E`**) applies the current LUT and intensity to every image in the set and writes them to a folder you pick, skipping (and counting) anything that fails rather than aborting the run.

---

## 🔬 Derive a LUT from a JPG

This is what makes LUTzy unusual. Most apps *apply* LUTs; LUTzy can also **manufacture** one.

**The idea:** your camera shot a RAW and, at the same instant, rendered its own JPEG using the manufacturer's color science (or whatever film simulation / picture profile you had dialed in). That JPEG *is* a look. LUTzy compares the neutral RAW against that JPEG and bakes the difference into a portable `.cube` file you can apply to any other photo.

**Menu:** `File ▸ Derive LUT from JPG…` (**`⌘D`**) → pick the RAW, pick the JPEG, hit **Derive**.

```
  RAW ──► CIRAWFilter (neutral baseline) ─┐
                                          ├─► align ─► sample smooth regions ─► build 33³ cube ─► .cube
  JPEG ─► decode ─► edge mask ────────────┘                                         │
                                                                                    └─► Analysis report
```

Under the hood the extractor:

1. Renders the RAW through the **same** default `CIRAWFilter` pipeline LUTzy uses everywhere — so the derived LUT drops straight back into the normal apply path with no baseline mismatch.
2. Checks the pair actually describes one frame (same aspect ratio) and refuses mismatched files rather than silently stretching one onto the other. Lanczos-scales both onto a common working extent — capped at 3000 px on the long edge, since 200k samples describe the color mapping just as well from a 3000 px render as from a 9000 px one — and finds the integer-pixel alignment by luma cross-correlation.
3. Builds an **edge mask** from the JPEG (so in-camera sharpening can't contaminate the color samples) and draws ~200k samples from smooth regions only.
4. Accumulates them into a **33³ color cube**, smooths any sparse cells from their neighbors, and anchors the rest to identity.

### The analysis report

Every derivation comes with a readout (rendered with Swift Charts) so you understand *what the look actually does*:

| Metric | Meaning |
|---|---|
| **Tone curve** | Per-channel R/G/B input→output mapping, plotted against the identity line |
| **Saturation** | Chroma ratio in smooth regions — `>1` more saturated, `<1` more muted |
| **Sharpening** | High-frequency energy ratio (same operator, same pixels, both images) — **measured but deliberately *not* baked into the LUT** (a LUT can't sharpen; apply it separately if you want to match) |
| **Coverage** | % of cube cells filled by real samples vs. interpolated |
| **Samples** | How many smooth-region pixels survived the edge mask |
| **Camera** | Make / model and EXIF contrast, saturation, sharpness, and white-balance tags from the JPEG |

The result previews live on your current image immediately and stays a scratch LUT until you click **Save to LUT Folder…**, at which point it joins your sidebar library like any other `.cube`.

---

## ⌨️ Keyboard shortcuts

| Key | Action |
|---|---|
| `↑` / `↓` | Previous / next LUT |
| `←` / `→` (or `[` / `]`) | Previous / next image (when a set is loaded) |
| `Space` (hold) | Show original (single view) |
| `V` | Toggle side-by-side / single view |
| `⌘I` | Toggle the histogram & EXIF inspector |
| `⌘O` | Open image |
| `⌘⇧I` | Import from Photos |
| `⌘⌥I` | Open source folder |
| `⌘R` | Re-scan the source folder |
| `⌘⇧L` | Choose LUT folder |
| `⌘D` | Derive LUT from JPG |
| `⌘S` | Export |
| `⌘⇧E` | Export all |

> Arrow/letter shortcuts are handled by a window-level `NSEvent` monitor (SwiftUI's `.onKeyPress` doesn't fire reliably inside a `NavigationSplitView`); `⌘`-shortcuts flow through the standard menu bar.

---

## 🚀 Build & run

LUTzy is a Swift Package — no `.xcodeproj` to manage.

**Quickest (CLI):**
```bash
swift run
```
Builds and launches the app for fast iteration. Note: the SwiftUI executable target runs without the bundled asset catalog or sandbox entitlements, so the app icon and security-scoped bookmark persistence won't be active in this mode.

**Recommended (Xcode) — full app behavior, icon, and App Sandbox:**
```bash
open Package.swift     # or: xed .
```
Then select the **LUTzy** scheme and **Run** (`⌘R`). For a sandboxed build, add the **App Sandbox** capability and point it at the included [`LUTzy.entitlements`](Sources/LUTzy/LUTzy.entitlements) (user-selected read/write + app-scope bookmarks).

**Tests:**
```bash
swift test
```
188 tests, no fixtures to download — everything they need is generated into a temp directory. CI runs
debug build → tests → release build on every push and PR.

**Requirements:**

|  | |
|---|---|
| **To run LUTzy** | macOS **14.0+** — unchanged, and what the deployment target targets |
| **To build LUTzy** | **Xcode 26+** (macOS 26 SDK) |

Those are deliberately different. Building against a current SDK while deploying to macOS 14 is the
normal Apple model, and the stricter one: the compiler refuses any API newer than macOS 14 unless it
is `#available`-guarded. One RAW develop control (`CIRAWFilter`'s highlight recovery) only exists in
the macOS 26 SDK, so an older Xcode cannot compile the package — while the app it produces still runs
on macOS 14.

---

## 🗂 Project structure

LUTzy is split into a `LUTzyKit` library and a thin `@main` executable, so the app's own code can be
unit-tested — `@testable` cannot import an executable target.

```
Sources/
├── LUTzy/                      # thin entry point only
│   ├── LUTzyApp.swift          # @main App + AppDelegate — window, default size, commands
│   ├── Assets.xcassets/        # App icon + accent color
│   └── LUTzy.entitlements      # App Sandbox + user-selected file access
└── LUTzyKit/                   # everything of substance
    ├── Models/
    │   ├── CubeLUT.swift           # .cube parser + writer → CIColorCube filter (also in-memory init)
    │   ├── WorkingSpace.swift      # the one colour space: LUT interpolation + output encoding
    │   ├── ImageProcessor.swift    # Singleton: RAW/standard load, preview, thumbnails, histogram, export
    │   ├── LUTLibrary.swift        # Scans LUT folder, groups by category, sandbox bookmark persistence
    │   ├── ImageCollection.swift   # Multi-image set with async thumbnail generation
    │   ├── ImageMetadata.swift     # EXIF/TIFF/GPS read + display formatting for the inspector
    │   ├── Histogram.swift         # 256-bin per-channel histogram data model
    │   ├── RecipeExtractor.swift   # (RAW, JPG) → 3D LUT derivation pipeline
    │   └── RecipeReport.swift      # Analysis data model (tone curve, ratios, EXIF camera info)
    ├── ViewModels/
    │   ├── AppViewModel.swift      # Central @MainActor state: image, LUT, preview, histogram
    │   ├── ExportCoordinator.swift # Single + batch export, and the naming they share
    │   └── DeriveCoordinator.swift # "Derive LUT from JPG" flow, scratch-until-saved result
    └── Views/
        ├── ContentView.swift       # Split-view layout + toolbar                          [public]
        ├── MenuCommands.swift      # File menu + its notification names                   [public]
        ├── StatusBar.swift         # Status line + key hints along the bottom
        ├── KeyboardShortcuts.swift # Window-level NSEvent monitor for arrow/letter keys
        ├── LUTSidebar.swift        # Searchable, category-grouped LUT list
        ├── PreviewView.swift       # Side-by-side / single canvas, drag-drop, badges
        ├── FilmstripView.swift     # Horizontal thumbnail strip for batches
        ├── SourceBrowserView.swift # Docked source-folder file list, grouped by subfolder
        ├── InfoInspectorView.swift # Histogram canvas + EXIF rows
        ├── RecipeExtractorSheet.swift  # "Derive LUT from JPG" modal (pickers, progress, report)
        └── RecipeReportView.swift  # Analysis card — Swift Charts tone curve + stat badges

Tests/
└── LUTzyKitTests/              # XCTest; fixtures are generated, never committed
    ├── Fixtures.swift          # builds .cube files and orientation-tagged JPEGs in a temp dir
    ├── CubeLUTTests.swift      # parser, domain handling, index ordering, intensity, round-trip
    ├── WorkingSpaceTests.swift # preview/export parity, LUT-interp ↔ output lockstep
    ├── ImageLoadingTests.swift # EXIF orientation across load/thumbnail/export, histogram
    ├── LibraryScanTests.swift  # async folder scans, error surfacing, collection navigation
    ├── RecipeExtractorTests.swift   # cube assembly, neighbour smoothing, working resolution
    ├── ExportCoordinatorTests.swift # single + batch export, failure handling, collisions
    ├── DeriveCoordinatorTests.swift # derive lifecycle, scratch-until-saved, save
    ├── AppViewModelTests.swift # coordinator wiring — status, errors, sidebar refresh
    └── ExportNamingTests.swift # batch-export collision handling
```

`ContentView` and `LUTzyCommands` are the only `public` symbols — the executable needs exactly those
two and nothing else.

`docs/CODE_REVIEW.md` records the standing findings from the last full review — what was fixed, and
what is still outstanding.

## 🏗 Architecture notes

- **Three stable workspaces.** Primary navigation contains only Viewer, LUT Manager, and LUT Editor. Image List/Gallery lives inside Viewer; All LUTs, Starred, folders, and LUT import live inside the LUT Library column, so changing library scope never steals the selected workspace.
- **MVVM with coordinators.** [`AppViewModel`](Sources/LUTzyKit/ViewModels/AppViewModel.swift) holds the image, LUT, and preview state, and owns four collaborators: `LUTLibrary`, `ImageCollection`, [`ExportCoordinator`](Sources/LUTzyKit/ViewModels/ExportCoordinator.swift), and [`DeriveCoordinator`](Sources/LUTzyKit/ViewModels/DeriveCoordinator.swift). The coordinators report *what* happened through `onStatus`/`onError` closures; deciding how to present it stays with the view model. Views observe, and the menu bar talks to it via `NotificationCenter`.
- **Panels are a seam, not a dependency.** Every operation that needs a file dialog is split into a `perform…` core taking an explicit URL and a thin `…Dialog` wrapper that runs the panel. `NSOpenPanel`/`NSSavePanel` can't run headless, so this is what makes export and save testable at all.
- **Core Image end to end.** RAW demosaicing (`CIRAWFilter`), LUT application (`CIColorCubeWithColorSpace`), scaling (`CILanczosScaleTransform`), and all export encoding run through one Metal-backed `CIContext`.
- **One colour seam.** [`WorkingSpace`](Sources/LUTzyKit/Models/WorkingSpace.swift) is the single source of truth for both the LUT interpolation space and the output encoding space, so they cannot drift apart; every render and export site takes it, defaulting to sRGB. Cube data is laid out R-fastest → G → B, matching both the `.cube` spec and Core Image's expected ordering.
- **Images are rendered upright.** `CIRAWFilter` honors EXIF orientation; plain `CIImage(contentsOf:)` does not, so every non-RAW decode goes through `ImageProcessor.orientedLoadOptions`. Preview, filmstrip thumbnail, reported dimensions, and export all agree.
- **Work stays off the main actor.** Decoding, preview rasterization, folder scans, LUT parsing, export, and recipe derivation all run detached and publish results back to `@MainActor`; the intensity slider is debounced and each render cancels the one before it. Previews are capped at 1600×1200; exports are always full resolution.
- **No third-party code.** Everything ships with the system: SwiftUI, Core Image, AppKit, PhotosUI, Swift Charts, ImageIO, Metal, simd.

### Colour parity with `lut-viewer`

Compare the same named stage in both applications; their default comparison views are deliberately
different:

- LUTzy's **Original** is the decoded source image. `lut-viewer`'s left-hand **neutral base** is the
  source converted to V-Log and rendered through `utility-vlog-neutral.cube`. That neutral render is
  a reconstructed baseline, not the untouched source, so saturated and clipped colours can differ.
- LUTzy applies cubes through Core Image's trilinear path. For like-for-like graded output, switch
  `lut-viewer`'s **interpolation** control from its tetrahedral default to **trilinear** and compare
  explicit sRGB output.
- Standard-image parity is pinned by shared stage-labelled golden vectors. RAW output remains
  decoder-dependent: LUTzy uses `CIRAWFilter`, while `lut-viewer` uses `rawpy` plus embedded-preview
  exposure matching. Preview and export must agree within each app, but RAW pixels are not expected
  to be identical across the two decoders.

---

## 📦 Preparing for the App Store

1. Drop a 1024×1024 source icon into [`Assets.xcassets/AppIcon.appiconset`](Sources/LUTzy/Assets.xcassets/AppIcon.appiconset).
2. Set your **Bundle Identifier** and **Team** in the target's Signing & Capabilities.
3. Keep **App Sandbox** enabled (the included entitlements already grant user-selected file access + app-scope bookmarks).
4. **Product ▸ Archive ▸ Distribute App ▸ App Store Connect.**

---

## 📄 License

LUTzy is released under the [MIT License](LICENSE) — free to use, modify, and distribute.

---

<div align="center">
<sub>Built with SwiftUI · Core Image · Metal — and nothing else.</sub>
</div>
