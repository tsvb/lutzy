# LUTzy Phase 2 — non-destructive render pipeline + RAW develop

**Status:** partly built. Steps 0–10b of the migration are done — the preview, both export paths and the
histogram all render from the document, `ImageProcessor` is gone, derive registers its result by ID,
both inspectors (RAW develop and Adjustments) ship, and the whole package builds in **Swift 6 language
mode** with no diagnostics and no escape hatches. Only undo (Step 11) is outstanding.

This is a distillation. The original draft ran 4,180 lines of multi-agent output that contradicted
itself across sections and spent a good fraction of its length arguing with earlier drafts about bugs
that never existed. Everything load-bearing is below; the original is in git history at `05ac1d6`.

**Baseline note:** the original was written against the pre-review codebase. Several of its premises
have since been fixed and are marked ✅ below — do not re-solve them.

---

## 1. What Phase 2 is for

LUTzy applies one LUT to one image and bakes the result. Phase 2 makes the edit a **value** instead of
a baked image, which buys four things at once:

1. **Preview/export parity becomes structural.** Today `renderPreview` and `export` are two code paths
   that merely agree. After: one `buildImage` call differing only by a scale value.
2. **RAW develop controls** — exposure, temperature, contrast, noise reduction — via `CIRAWFilter`'s
   native properties, which must be set *before* `outputImage` and so cannot be a post-hoc node.
3. **Undo, presets, and per-image edits for free** from a `Codable` document.
4. **One color seam** instead of four scattered `sRGB` literals plus two implicit sites.

---

## 2. Baseline — what is already true

| | |
|---|---|
| ✅ `LUTzyKit` library + thin `@main` executable, 95 XCTest cases, `swift test` in CI | Step 0 is **done** |
| ✅ Preview rasterization and decode run off the main actor; intensity slider debounced | the "full filter graph on the main thread" bug is **fixed** |
| ✅ LUT intensity ships today — `lutIntensity`, `CubeLUT.apply(to:intensity:)`, toolbar slider | the original called this "NEW behavior… exists nowhere". It exists. |
| ✅ EXIF orientation baked at load for every non-RAW decode | the original's "standard images have NO orientation baking" is stale |
| ✅ `AppViewModel` split into `ExportCoordinator` + `DeriveCoordinator` | the `[processor]`-capture hazard it inherited is gone as of Step 7 |
| ✅ `ImageDecoder.rawExtensions` internal; `developRAWNeutral` defines the neutral RAW baseline for the eager decode and for derive | the render stack builds its own `CIRAWFilter` in `RenderPipeline.rawFilter(for:)` — the only site that handles a `.data` backing — and matches the baseline only because `RAWDevelopSettings.neutral` sets nothing. Pinned by one URL-only test that skips without a local RAW. Was `ImageProcessor` until Step 7 |
| ✅ Derive: cancellable, geometry-validated, capped at a 3000 px working resolution | |
| ✅ The value-state types exist (`EditDocument` and friends) — but nothing uses them yet | Step 2 is **done** |
| ✅ `RenderPipeline.buildImage` and `LUTFilterCache` exist — also unused | Step 3 is **done** |
| ✅ `actor RenderEngine` + `RenderEngining` exist, with a fake for tests | Step 4 is **done** |
| ✅ **The preview renders from `EditDocument`** through the engine — develop, adjustments, LUT, intensity | Step 5 is **done** |
| ✅ **Export and the histogram render from `EditDocument` too** — single *and* batch; `processedImage` deleted | Step 6 is **done** |
| ✅ **`ImageProcessor` dissolved** — `ImageDecoder` + `Thumbnails` + `ExportFormat`; one `CIContext` in the render stack | Step 7 is **done** |
| ✅ **Derive registers its result by ID** — content-hashed `derived://`, a session registry, save re-points | Step 9 is **done**; it fixed a shipped bug, see below |
| ✅ Both inspectors ship — RAW develop (10a) and Adjustments (10b) | Only undo is outstanding — Step 11 |

~~**Still true and still worth fixing:** `ImageProcessor` is a non-`Sendable` `final class` singleton
holding a `CIContext`, captured into `Task.detached` in several places.~~ **Fixed in Step 7** — the
type is gone. Its GPU duties went to `actor RenderEngine`, its thumbnails to `enum Thumbnails`
(`CGImageSource` only, never Core Image), its output vocabulary to `ExportFormat`, and what remained
— the format vocabulary, `orientedLoadOptions`, `developRAWNeutral`, and the eager decode — to
`enum ImageDecoder`, which is stateless and so has no instance to share.

✅ **Step 8 turned it on, and went further than planned.** The plan was Swift 5 language mode with
`-strict-concurrency=complete`, which reports data-race problems as *warnings*. Measured first:
`LUTzyKit` compiles with **zero** diagnostics in full **Swift 6 language mode**, where they are
errors. So `Package.swift` moved to a 6.0 tools version and declares `.swiftLanguageMode(.v6)` on all
three targets — library, executable and tests — rather than the weaker flag.

The standalone `swiftc -typecheck` invocation this section used to carry is retired: `swift build`
enforces it now, on every target rather than just the library, which is where the last diagnostic
actually turned out to be.

Two real fixes fell out, both in code the earlier steps had not touched:

- `KeyMonitor.deinit` removed its `NSEvent` monitor. A `deinit` is `nonisolated` — it can run on any
  thread — so it may not touch the non-`Sendable` `Any?` token AppKit returns. Teardown became an
  explicit `stop()` on the main actor, called from `onDisappear`. That is the better shape anyway:
  `NSEvent.removeMonitor` wants the main thread, and reaching it from a `deinit` never guaranteed one.
- `PreviewCostBenchmark.timeAsync` passed a non-`Sendable` closure to an unstructured `Task`. Marked
  `@Sendable`; every call site already captured only values.

**Zero escape hatches**, which is what makes the mode mean anything: no `@unchecked Sendable`, no
`nonisolated(unsafe)`, no `@preconcurrency` anywhere in `Sources`. `PackageSettingsTests` asserts
both the manifest settings and the absence of opt-outs, because neither is observable at runtime.

---

## 3. Architecture (binding)

Four layers, strict dependency direction:

```
EditDocument (value: Codable, Sendable, Equatable)   ← the look; serializable, undoable
        │  described by
        ▼
RenderPipeline.buildImage(...)        ← pure fn: EditDocument → ONE lazy CIImage
        │  evaluated by
        ▼
actor RenderEngine (owns the ONE CIContext)   ← rasterize at .preview or .full
        │
        ├── CGImage → @MainActor wraps NSImage   (preview)
        └── Data    → write(to:)                 (export)
```

`RecipeExtractor` sits **outside** this stack. It never imports `EditDocument`, never calls
`RenderEngine`, and keeps its own `CIContext` and its own sRGB sampling space.

### The types

```swift
struct EditDocument: Codable, Sendable, Equatable {
    var version: Int = 1                            // migrate explicitly as the schema grows
    var rawDevelop: RAWDevelopSettings = .neutral   // only meaningful for RAW sources
    var adjustments: [AdjustmentNode] = []          // ordered tone/color stages
    var lut: LUTSettings = .none                    // LUT by ID + intensity
}

/// nil = "leave CIRAWFilter at its decoder default", so .neutral is byte-identical
/// to today's developRAWNeutral output.
struct RAWDevelopSettings: Codable, Sendable, Equatable { /* exposure, neutralTemperature, … */ }

/// CLOSED enum, not [any AdjustmentNode] — see §4.1.
enum AdjustmentNode: Codable, Sendable, Equatable {
    case exposure(ev: Double)
    case colorControls(brightness: Double, contrast: Double, saturation: Double)
    case highlightShadow(highlights: Double, shadows: Double)
    case temperatureTint(temp: Double, tint: Double)
    case vibrance(amount: Double)
}

struct LUTSettings: Codable, Sendable, Equatable { var lutID: LUTID?; var intensity: Double = 1.0 }
struct LUTID: Codable, Sendable, Hashable { let raw: String }   // String, NOT UUID — see §4.3

/// How to REPRODUCE the source, so RAW can be re-developed per render.
/// A URL or Data, never a live CIImage: nothing non-Sendable enters app state.
struct ImageSource: Sendable, Equatable {
    enum Backing: Sendable, Equatable { case url(URL), data(Data) }   // .data covers Photos imports
    enum Kind: Sendable, Equatable { case raw, standard }
    let backing: Backing; let kind: Kind; let nativeExtent: CGSize
}

enum RenderScale: Sendable, Equatable { case preview(maxSize: CGSize), full }
enum WorkingSpace: String, Codable, Sendable { case sRGB, displayP3; static let current = WorkingSpace.sRGB }
```

`RenderPipeline.buildImage(source:document:lut:scale:space:) -> CIImage?` folds those into a single
lazy graph — source → RAW develop → ordered nodes → LUT-with-intensity — rasterizing **nothing**
in between. `actor RenderEngine` owns the only `CIContext` and evaluates it at one of two scales.

Preview downscales **early**: `CIRAWFilter.scaleFactor` before `outputImage` for RAW, a Lanczos step
right after load for standard images. Adjustment and LUT nodes then operate on ~1600×1200 px rather
than full extent.

---

## 4. The five decisions that matter

### 4.1 Adjustments are a closed enum, not protocol existentials

`[any AdjustmentNode]` cannot synthesize `Equatable`/`Codable` and needs a manual type-tag coder —
which undermines the value-state spine that earns undo and Swift 6 cleanliness in the first place. A
closed enum is equally ordered and composable, costs one case plus one switch arm to extend, and gets
the conformances free. For a small, known set of `CIFilter` wrappers this is strictly better.

### 4.2 RAW develop is not a node

`CIRAWFilter` must be rebuilt from the source and configured **before** `outputImage`; you cannot chain
develop onto an already-developed `CIImage`. So `rawDevelop` is a separate field consumed at the source
stage, and `ImageSource` carries a URL/Data rather than an image. This asymmetry is forced by the
framework, not a modelling preference.

### 4.3 The LUT is referenced by ID, and the ID is a `String`

`CubeLUT` holds a non-`Codable` float table; embedding it would make `EditDocument` non-`Codable` and
bloat every undo snapshot. So the document stores a `LUTID` resolved through a registry.

**The ID must be deterministic** — derived from `CubeLUT.id` (a file path). A random UUID would mint a
new ID on every `LUTLibrary.scan`, and since `saveDerivedLUT` triggers a rescan, persisted and undo
documents would silently stop resolving. Only in-memory derived LUTs get a synthetic ID.

### 4.4 One color seam, threaded rather than disciplined

There are **four** explicit `CGColorSpace.sRGB` literals today and **two implicit sites**:

| site | file | role |
|---|---|---|
| LUT interpolation | `CubeLUT.swift:152` | the space the cube interpolates in |
| Export encoding | `ImageProcessor.swift:259` | output encoding — now `RenderEngine.encode` |
| Histogram render | `ImageProcessor.swift:188` | analysis only — now `RenderEngine.histogram` (Step 6) |
| Derive sampling | `RecipeExtractor.swift:101` | **stays pinned to sRGB, not `.current`** |
| *(was implicit)* | `ImageProcessor.renderPreview` `createCGImage` | **passed no colour space** — preview used the CIContext default while export forced sRGB |
| *(was implicit)* | `ImageProcessor.renderToNSImage` `createCGImage` | same |

✅ **Step 1 closed all six.** Every `CGColorSpace(name:)` literal in the module now lives in
`WorkingSpace.swift` — verified by sweeping `CGColorSpace(`, `workingColorSpace`, `outputColorSpace`,
`NSColorSpace` and `kCGColorSpace*` over `Sources/`, which hit only that file. The five render,
interpolation and encoding sites take a `WorkingSpace` defaulting to `.current`; **derive is the
exception and reads `WorkingSpace.sRGB` explicitly, by design** — row four above, and §4.4 below, both
say so. This paragraph used to read "each site takes a `WorkingSpace`", contradicting its own table.

The table is a **snapshot of the problem as it stood at Step 1**, not a map of HEAD — four of its six
rows point at `ImageProcessor.swift`, deleted in Step 7, and the two line numbers that still resolve
are the pre-fix ones. Read it as history; do not refresh the line numbers piecemeal.

The two implicit sites were a **latent preview/export mismatch** — byte-identical at sRGB, divergent
otherwise. Measured: reintroducing the bare `createCGImage` call moves the preview by up to **38/255**
against the export in Display P3, and by **0** in sRGB. That is exactly why a test asserting only
today's sRGB behaviour would not have caught it, and why the lockstep tests drive a non-default space
through both halves of the seam.

**Critical invariant:** LUT-interpolation space and output-encoding space must move in lockstep. They
are independent literals today that merely both happen to be sRGB. Threading one `WorkingSpace` value
through `buildImage` makes desync structurally impossible.

**Honest scope:** the seam governs LUT interpolation and output encoding, *not* source decode. A P3
JPEG is still funnelled to sRGB for interpolation, same as today. Don't oversell it.

**Derive is deliberately excluded.** A derived `.cube` is *fit* in the baseline-render space and later
*applied* in `WorkingSpace.current`; for it to be self-consistent, fit-space must equal apply-space.
Both are sRGB today. Never blindly thread `.current` into the derive sampler — its neutral RAW baseline
is itself an sRGB-default render. A P3 flip requires re-fitting derive **or** stamping the build space
onto the `CubeLUT`.

### 4.5 The GPU is the only isolation boundary

`actor RenderEngine` owns the single Metal `CIContext`. `CIImage`/`CIFilter`/`CIContext` are born and
die inside it. Only `Sendable` values cross in (`EditDocument`, `ImageSource`, `WorkingSpace`,
`RenderScale`, `LUTID`, `URL`/`Data`); a `sending CGImage?` or `Data` crosses out.

`CGImage` is **not** `Sendable` (verified, Swift 6.3) — use `-> sending CGImage?` (region-based
isolation), which keeps both the zero-`@unchecked` promise and the zero-copy benefit over returning bytes.

✅ **Step 7 did this.** `ImageProcessor` is gone. GPU duties moved to the actor; the format vocabulary
(`rawExtensions`/`supportedExtensions`/`supportedTypes`), `orientedLoadOptions`, `developRAWNeutral`
and the eager open-time decode became statics on `enum ImageDecoder`; `ExportFormat` was promoted to
a top-level type; and thumbnails went to `enum Thumbnails`.

**Thumbnails deliberately did *not* move onto the actor.** They read a file's embedded preview through
`CGImageSource` — for a RAW that is the camera's own JPEG, which is why a 30 MB DNG thumbnails in
milliseconds without being demosaiced. No `CIImage`, no `CIContext`, nothing for the engine to add;
routing them through it would only queue every filmstrip tile behind the preview render. What Step 7
changed is that both `ImageCollection` call sites stopped capturing a non-`Sendable` singleton into a
`Task.detached`. `RenderStackTests` pins both halves: the set of files constructing a `CIContext`, and
that `Thumbnails` names no Core Image type.

The LUT filter cache lives on the **actor**, keyed by `LUTID` × color space — not on `CubeLUT`, which
stays an immutable `Sendable` value.

---

## 5. Invariants

- **Resolution independence.** Every `AdjustmentNode` must use normalized units. The current set
  (exposure, color controls, highlight/shadow, temp/tint, vibrance) is inherently scale-invariant. Any
  future pixel-sized node — grain, blur, sharpen — **must** express its radius normalized, or an
  early-downscaled preview and a full-res export diverge silently. This is the price of downscaling early.
- **RAW parity is tolerance-based by design.** `CIRAWFilter.scaleFactor` draft demosaic differs subtly
  from a full decode, so a scaled RAW preview is not byte-proof of the export. Test *wiring symmetry*
  (a knob moves both paths), not byte equality.
- **Derive baseline immunity.** `RecipeExtractor` must never receive `document.rawDevelop`. Enforced by
  `DeriveBaselineImmunityTests`, which reads the source: it pins derive's parameter labels to exactly
  `{rawURL, jpgURL, options, progress, isCancelled}`, and pins `RecipeExtractor.swift` and
  `DeriveCoordinator.swift` to naming neither `EditDocument` nor `RAWDevelopSettings` nor `rawDevelop`.
  There is no import to omit — `EditDocument` is the same module — so the construction half is a
  convention, and that test is what holds it. It reads text because a *defaulted* develop parameter has
  no runtime trace: `.neutral` renders byte-identically to `ImageDecoder.developRAWNeutral`, so the
  derived cube is bit-identical and there is no pixel to assert on. Needs no DNG, so it runs on CI.
  **This invariant went uncovered from Step 3 until the opposition pass**, and the spec asserted the
  test existed for the whole of that time; `DeriveInvarianceTests` pins the *pipeline's* develop wiring
  and is invariant to derive's signature — measured, with the DNG present, against a defaulted
  `develop:` parameter: it stayed green.
- **Empty document is identity.** An `EditDocument()` with no LUT must produce the source unchanged.

---

## 6. Migration

Each step builds, passes, and ships on its own. Introduce the spine *under* the old behavior, cut over
leaf by leaf, delete the old path last.

| Step | Work | Ship gate |
|---|---|---|
| ~~0~~ | ~~`LUTzyKit` split + test harness~~ | ✅ **done** — 95 tests, CI green |
| ~~1~~ | ~~`WorkingSpace`; route all six colour sites through it~~ | ✅ **done** — export, preview pixels and histogram byte-identical at sRGB; parity + lockstep tests added |
| ~~2~~ | ~~`EditDocument`, `RAWDevelopSettings`, `AdjustmentNode`, `LUTSettings`, `LUTID`, `ImageSource` — **defined but unused**~~ | ✅ **done** — plus `RenderScale`; 132 tests, nothing in the app references them, app launches unchanged |
| ~~3~~ | ~~`RenderPipeline.buildImage` + the actor-side LUT filter cache — **defined but unused**~~ | ✅ **done** — 162 tests; identity is pixel-exact, intensity endpoints exact, 21 mutations caught |
| ~~4~~ | ~~`actor RenderEngine` alongside the old path; a `RenderEngining` protocol so tests inject a fake~~ | ✅ **done** — 175 tests; preview/export parity asserted in both spaces; 12 mutations caught |
| ~~5~~ | ~~Cut **preview** over. Keep computed `sourceImage`/`selectedLUT` shims so views compile~~ | ✅ **done** — 188 tests; 15 mutations caught; needed a **developed-source memo**, see below |
| ~~6~~ | ~~Cut **export** over; delete `processedImage`~~ | ✅ **done** — 203 tests; 25 mutations caught; **both** export paths cut over, and the histogram came with them (see below) |
| ~~7~~ | ~~Move thumbnails (**both** `ImageCollection` sites); dissolve `ImageProcessor` GPU duties~~ | ✅ **done** — 208 tests; 18 mutations caught, 2 shown equivalent by measurement; `RenderStackTests` asserts the context count |
| ~~8~~ | ~~Flip strict concurrency on~~ | ✅ **done** — full **Swift 6 language mode** (errors, not warnings) on all three targets; 214 tests; 9 mutations caught, 1 untestable and named |
| ~~9~~ | ~~Wire derive into the new state: register the derived LUT by ID, keep the scratch-file bookkeeping~~ | ✅ **done** — 230 tests; 19 mutations caught, 1 shown equivalent by inspection; fixed a **shipped** bug where a derived LUT never resolved (see below). ⚠️ **That tally was produced by a classifier since found to be broken** — `scripts/mutate-step9.sh` tested for "skipped" before "failed", so in any suite mixing RAW-gated with ordinary tests it could score a run by the wrong branch, and `SKIPPED` was excluded from the exit gate. Fixed by back-porting `mutate-step10a.sh`'s failure-first classifier and adding `SKIPPED` to the gate; **the tally has not been re-measured since** |
| ~~10a~~ | ~~RAW develop inspector + the per-image capability probe~~ | ✅ **done** — `RAWCapabilities` crosses the actor boundary carrying nine gates and twelve per-image seeds; the probe measures **~25 ms warm** against **~183 ms** for a full develop, so it runs once per open and never per render. 33 mutations, 32 caught on the first run and the one survivor closed with the test it exposed. **The RAW-gated tests `XCTSkip` on CI**, which has no DNG — a green tick there says nothing about them |
| ~~10b~~ | ~~Adjustments inspector — fixed slots, one node of each, canonical pipeline order~~ | ✅ **done** — 322 tests (up from 272; 308 at 10b, plus 14 added by the opposition pass and the review-alignment work that followed it). **22 skip without a DNG, 3 with one present** — measured both ways, by hiding `realworldtest/` and re-running. The 3 that always skip are `PreviewCostBenchmark`'s, gated on `LUTZY_BENCH` rather than on a RAW; the other 17 are the RAW-gated ones. This entry previously said "3 skipped without a DNG", which was wrong under either reading. Nine per-parameter rows over the five `AdjustmentNode` cases, driving `EditDocument.adjustments` live. `AdjustmentNode`, `RenderPipeline`, `RenderEngine` and `EditDocument` carry no logic, signature or behaviour change — purely additive, aside from **three** stale §8.7 doc comments; only the two in `Sources/` were corrected at the time, and the third, on `RenderPipelineTests.testRaisingKelvinCoolsTheImage`, survived until the opposition pass. The commit that fixed them said "the two doc comments", having grepped `Sources/` alone. No mutation run was performed here; `AdjustmentControl`'s sparse-array contract and the slider map are covered instead by pure-value tests needing no GPU, image or RAW, so — unlike 10a's RAW-gated tests — they run on CI. Closed §8.5's, §8.6's and §8.7's remaining open halves, see below |
| 11 | Per-image undo keyed by `Item.id`, plus an `EditDocumentStore` | ⌘Z scoped per image |
| 12 | *(deferred)* export descriptor, metadata/ICC | — |

Debounce **continuous edits only**. Open and filmstrip navigation must render immediately, or stepping
through a folder picks up latency for no reason.

### The cutover's one real trap, measured at Step 5

Rebuilding the source image per render is a **catastrophic** regression, and not an obvious one:
Core Image caches decoded intermediates against the `CIImage` *instance*, so a freshly-built source
each render re-decodes the file every time. Measured per preview render:

| source | rebuilt per render | reusing one instance |
|---|---|---|
| 30 MB DNG | 63–76 ms | ~1 ms |
| 6000×4000 | 151–167 ms | ~0.7 ms |

An intensity drag is many renders, so the naive cutover would have been plainly visible. `RenderEngine`
therefore memoizes the developed source, keyed on **(source, rawDevelop, scale)** and only for preview
scales — export runs once per action and would otherwise pin full-resolution intermediates.

With the memo the cutover is a wash per render (~1 ms either way) and *saves* ~200 ms when opening a
RAW, because the eager full-resolution decode is no longer on the path to first pixels. `swift test
--filter PreviewCostBenchmark` with `LUTZY_BENCH=1` reproduces the numbers.

**Step 6 inherited this, and measured it.** Export at `.full` is deliberately not memoized, so it
rebuilds its source every time — the exact shape of the regression above. On a 6000×4000 source:

| | per export |
|---|---|
| old *batch* (`loadImage` + `apply` + encode, per item) | 156 ms |
| new (`engine.encode` at `.full`, whole document) | 158 ms |
| old *single* (re-encoding `sourceImage`, already decoded at open) | 21 ms |

So Export All is a wash — the old batch loop decoded per item too — and a single ⌘S costs one extra
full decode, which is what buys it develop and adjustments. Footprint over eight distinct exports
grew 46 MB/export through the engine against 56 MB/export on the old path: both retain roughly one
full-resolution intermediate per export, neither gives it back, and `CIContext.clearCaches()` does
not reclaim it. That is Core Image's own accounting and predates the cutover.
`PreviewCostBenchmark.testMeasureExportCost` reproduces all of it.

### What Step 9 found: a derived LUT never resolved

Step 9's headline was not migration work. It was a **shipped bug**, live on `main` since derive was
built, that the migration merely made legible.

`DeriveCoordinator.derive` named its result after the scratch temp file (`sourceURL: scratch`), so
`CubeLUT.init` set `id` to a temp path and `LUTID.isDerived` read **false**. `selectLUT` therefore
filed it under nothing and `resolvedLUT` fell through to a library lookup for a path no library
contains. A successful derive left the preview **ungraded** with nothing selected in the sidebar.
Measured before the fix, and again after, on the same construction:

| | before | after |
|---|---|---|
| `isDerived` | false | true |
| `selectedLUT` after `onDerived` | `nil` | the derived LUT |
| preview delta vs. ungraded | **0/255** | graded |

Two tests covered this area and both were green, because both built their fixture with
`CubeLUT(cube:size:name:)` — no `sourceURL`, hence a `derived://` id — where production produced a
path. **The fixture differed from production in exactly the field under test.** That is
`CODE_REVIEW.md` §2's "wrote a value that equals the default" one level up, and it is now prevented
structurally rather than by discipline: `DeriveCoordinator.makeDerivedLUT` is the single constructor,
used by production and every test.

What the step settled:

- **Identity is content-derived.** A derived LUT's id is
  `derived://<name>/<first 64 bits of the sha256 of the cube table>` — `CubeLUT` takes
  `digest.prefix(8)`, so the hex field is 16 characters, not 64. That is deliberate and documented at
  the call site: it distinguishes the handful of derives in one session, not the world's LUTs.
  (`CryptoKit`; **not** `Hasher`, which is seeded per process and would be stable within a launch and
  silently different across launches.) This reverses a documented property — two identically-built
  in-memory LUTs are now *one* identity, not two — which two tests assert deliberately. It buys
  determinism per cube value, which is §4.3's real objection to `UUID`. It does **not** buy
  resurrection by re-deriving: `RecipeExtractor` samples with `SystemRandomNumberGenerator`, so the
  same pair fits a different cube every run.
- **Save re-points, after re-parsing.** The saved file — not the in-memory cube — becomes what the
  document references, because `cubeFileContents` writes `%.6f` and the file is what a fresh launch
  would resolve. The reference becomes durable at the moment the LUT does. `DerivedLUTRegistry`
  (unbounded; a 33³ cube is ~575 KB and a derive costs tens of seconds) covers saves outside the LUT
  folder, where no rescan fires.
- **`invalidateLUTCache` is wired at last**, because Step 9 made it reachable: save a derive to
  `X.cube`, derive again, save over `X.cube` — same path, same `LUTID`, stale cube forever. It is on
  the `RenderEngining` protocol now (so the app calling it is assertable) and fires from a
  `LUTLibrary.onScanned` closure, which covers every scan rather than the sites someone remembered.
  Measured: without the flush the replaced-cube render differs from the original by **0/255**.
- **Scratch-file policy is unchanged.** A cancelled derive still writes nothing, a completed one is
  still kept for the sheet to reopen, and it is still left to the OS temp sweep. What changed is only
  that the temp path no longer *names* the LUT.
- `RecipeExtractor` did **not** move onto the engine, so `RenderStackTests` is untouched.

The ship gate, `DeriveInvarianceTests`, derives from the `realworldtest` pair and checks the cube
lands the same way through the new pipeline as it does over `developRAWNeutral` (tolerance 1,
interleaved in one process). A second assertion bounds mean absolute error against the in-camera JPG:
measured **1.25/255**, bounded at 3.0, against **5.30** with no cube at all — so the bound has real
discriminating power. **These tests skip on CI**, which has no DNG; the suite's green tick there says
nothing about derive.

### What Step 6 did with the histogram

`histogramSourceImage` read `processedImage`, so deleting the latter forced a decision. It became an
**engine call**: `RenderEngine.histogram` renders the document and tallies it inside the actor, and
`AppViewModel` drives it from the same `displayRequest` the preview uses. The old path would have
left the panel describing a full-resolution neutral decode with only the LUT on it while the screen
showed develop and adjustments too — the same divergence this step exists to close, one panel over.

It renders at the **preview** scale, not a histogram-sized one, and caps only the tally buffer. A
private 512 px scale would evict the developed-source memo on every tally and re-develop the RAW on
the next frame. `ImageProcessor.histogram` is gone; the tally is now a pure
`HistogramData(rgba8:width:height:bytesPerRow:)`, testable against a hand-built buffer.

---

## 7. Risks worth carrying

| Risk | Mitigation |
|---|---|
| **Random `LUTID`** → file-backed LUTs get new IDs on every scan, so saved documents silently lose their LUT | Deterministic `LUTID` from the path. Test that resolution survives a rescan. |
| **Fabricated `CIRAWFilter` API** copied from the original draft | Use the header-verified set in §9. Compile Step 2 early. |
| **Global undo stack** corrupts other images' edits on navigate-then-undo | Per-image, keyed by `Item.id` (not URL — nil for Photos imports) |
| **Photos `data:` imports** break if `ImageSource` is URL-only | `Backing.data(Data)`. Temp files misclassify RAW and need cleanup. |
| ~~**`ExportFormat` promotion** loses `Identifiable` and its raw values~~ | ✅ **done in Step 7**, in one commit. `testTheToolbarPickerContractSurvivedThePromotion` pins `allCases` order, id uniqueness, raw values and `utType` — all things that fail *silently* in a `Picker`. |
| **Stale A/B cache** shows a pre-edit graded image during Space-hold | Encode `isShowingOriginal` into the render-request identity, or render an `intensity = 0` document |
| **Silent LUT failure** if the old "LUT application failed" branch is dropped | Validate once at parse/load and report, rather than per render |

---

## 8. Open questions — need sign-off

1. **Intensity blend space.** The dissolve mixes in the CIContext working space (≈ linear light), *not*
   in the cube's interpolation space. Measured on the current build, a to-black LUT over white reads
   255 / 225 / **188** / 137 / 0 at intensity 0 / .25 / .5 / .75 / 1 — a perceptual mix would read ~128
   at half. This is shipping behavior today, so changing it later is a visible look change for every
   sub-100% render. Decide deliberately.
2. **`kCIContextWorkingColorSpace` precision.** Setting `extendedLinearSRGB` + `RGBAh` changes
   intermediate precision for every render and needs a soft-clip before the 8-bit encoders (16-bit TIFF
   hides the out-of-gamut shifts). *Recommend: defer, CI default for v1.*
3. **Display P3.** Flipping `WorkingSpace.current` moves LUT-interp and output in lockstep, but derived
   LUTs were fit in sRGB and would mis-map. Prerequisite: a `buildSpace` on `CubeLUT`, or re-fit derive.
4. ~~**New-image document policy.**~~ **Decided at Step 5: keep.** The document survives an open, so a
   look can be auditioned across a folder — which is what the app already did with its LUT selection
   and intensity, so the cutover changed nothing here.

   **Revisited at Step 10a.** The Step 5 rationale is about *look* — a LUT and its intensity mean the
   same thing on every image in a folder, so carrying them forward is correct. `rawDevelop` breaks
   that: exposure, white balance and the rest are decoder defaults **measured per file**, not a
   portable look, and Step 10a is the first thing that writes to them. Carrying `document` forward now
   also carries a stale seed. Set white balance to 3200 K on one RAW, press → to the next, and the new
   image renders at 3200 K while its own probed as-shot temperature — 5842 K on the Leica in
   `realworldtest/` — sits unused in `rawCapabilities`, never read because `neutralTemperature` is no
   longer `nil`. `EditDocument.originalForComparison` (§8.5) keeps `rawDevelop` for its baseline, so
   the A/B "original" is wrong the same way: it shows image B developed with image A's white balance,
   not image B's own as-shot rendering. Step 5 could not have reasoned about this — develop did not
   exist yet. **Deliberately deferred to Step 11:** that step adds per-image undo and an
   `EditDocumentStore`, which is the point at which "which document belongs to which image" stops
   being a single global answer and becomes a per-`Item.id` one — the natural place to also decide
   whether `rawDevelop` resets, and to what, on open. Left as-is until then.
5. ~~**"Original" for A/B.**~~ **Decided at Step 5: develop-applied.** `EditDocument.originalForComparison`
   keeps `rawDevelop` and strips adjustments and the LUT — holding Space shows the same negative
   without the *look*, not a different rendering of it. Sharing `rawDevelop` also keeps the swap cheap,
   since both sides hit the same developed-source memo. Invisible until the Step 10 inspector exists,
   which is why it was worth settling now rather than then. **Closed at Step 10b:** side-by-side
   triggers on any non-neutral document, not on "a LUT is set." `AppViewModel.isComparisonAvailable`
   implements it as `!document.adjustments.allSatisfy(\.isIdentity) || !document.lut.isIdentity` — exact, unlike the
   structural `document != originalForComparison` Step 10b first reached for, which read a LUT at 0%
   intensity as non-neutral (`isIdentity` treats it as contributing nothing; `!=` still sees `lutID`
   set) and offered a split view of two pixel-identical halves. One consequence worth naming: a
   develop-only edit correctly reads `false`, because `originalForComparison` keeps `rawDevelop`, so
   both halves render the same picture.
6. ~~**Adjustment list semantics.**~~ **Decided at Step 10b: fixed slots**, overturning the original
   recommendation to allow duplicates. Nine per-parameter rows over five nodes is a usable panel in one
   step; a stacking editor needs add/remove/reorder UI and list identity for an enum that is not
   `Identifiable`. The *model* still permits duplicates — `AdjustmentNode`'s doc comment stays true —
   so nothing is foreclosed.
7. ~~**`CITemperatureAndTint` direction.**~~ **Closed at Step 10b**, by measuring the *other* knob
   rather than changing this one. Step 3's table stands — raising the node's Kelvin still *cools*,
   pinned by `testRaisingKelvinCoolsTheImage` — and Step 10b measured `CIRAWFilter.neutralTemperature`
   on the Leica M11 DNG in `realworldtest/`, moving only that property:

   | target | mean R−B |
   |---|---|
   | 3200 K | −101.19 |
   | 9000 K | +54.22 |

   Raising `neutralTemperature` *warms* — the photographic convention — pinned by
   `RAWCapabilitiesTests.testRaisingNeutralTemperatureWarmsTheImage` (`XCTSkip`s without a DNG).
   Neither filter's wiring changed: `AdjustmentControl.sliderMapped(_:)` reflects the Adjust
   temperature slider about D65 instead, and that slider's range is **2000…11000 K** rather than
   Develop's 2000…50000 because the reflection must be closed — `13000 − K` maps 2000…50000 onto
   11000…−37000, and negative Kelvin is not a colour.
8. **Edit persistence across launches.** `EditDocument` is `Codable` to enable it; v1 in-memory only.
9. **RAW fixtures in CI.** Derive-invariance and RAW-parity tests need a license-clean small `.dng`+`.jpg`
   pair, else `XCTSkip`. Everything else in the suite generates its fixtures.

---

## 9. Verified facts — do not re-litigate

Checked against the SDK header and the real source. The original draft got several of these wrong in at
least one section, which is most of why it was so long.

**`CIRAWFilter`** (class is macOS 12+):
- The full `is*Supported` set **exists** — sharpness, moireReduction, contrast, detail, localToneMap,
  colorNoiseReduction, luminanceNoiseReduction, lensCorrection — and should gate its knob.
- `gamutMappingEnabled` is settable.
- EDR is a **single** knob, `extendedDynamicRangeAmount` (0...2), with no availability macro — callable
  **unguarded** on the macOS 14 target. There is no `isEDRModeEnabled` / `enableEDR`.
- Highlight recovery is the **only** knob needing `#available`. The header marks it `16_0`, which the
  Swift importer maps onto the renumbered **macOS 26** — `#available(macOS 26, *)` is what the
  compiler enforces, so that is what the code says. Every *other* property carries no per-property
  availability macro and dates from `CIRAWFilter` itself (`NS_CLASS_AVAILABLE(12_0, …)`), verified
  present as far back as the macOS 15.4 SDK.
- **SDK ≠ deployment target, and the SDK is a CI configuration choice.** Step 2 first shipped with CI
  on `macos-14` (Xcode 15.4, macOS 14.5 SDK), where the highlight-recovery properties are not in the
  imported interface *at all* — an availability check gates a call at runtime and cannot conjure a
  symbol the SDK never declared, so the reference failed to compile there while building clean on a
  current local Xcode. **Resolved by moving CI to `macos-26`** (which GitHub had deprecated `macos-14`
  in favour of anyway) while keeping the macOS 14 deployment target. That combination is the stricter
  one: the compiler now *refuses* newer API unless it is guarded. The cost is that the package
  requires Xcode 26+ to build; see `CLAUDE.md`. Step 10 is all new `CIRAWFilter` surface and depends
  on this arrangement.
- `isDustRemovalSupported` and `isBaselineExposureAvailable` **do not exist** — fabricated.

**This codebase:**
- `CubeLUT.id` is a `String` (file path, or `derived://…`). A `LUTID` wrapping `UUID` will not compile
  against it and would break resolution across rescans.
- `CGImage` is not `Sendable`; use `sending`.
- EXIF/ICC **cannot** be injected through `CIImageRepresentationOption` — that enum has no
  `kCGImageProperty*` channel. Metadata needs `CGImageDestination`, which is why it is Step 12.
  Note images are now baked upright at load, so a metadata path must force output `orientation = 1`
  rather than copying the source tag onto already-rotated pixels.
- `PreviewView` has no undefined symbol and no FIXME. The original draft argued with itself about this
  across four sections. It compiles; it always did.
- `CIFilterBuiltins.h` documents no parameter ranges, only prose — the numbers live in the runtime
  `CIFilter.attributes` dictionary.
- **`kCIAttributeSliderMin` is a suggested UI bound, not a limit** — read `kCIAttributeMin` before
  assuming a value is out of range. `inputContrast` reports slider 0.25…4 but a hard min of **0**,
  and rendering 0.20 / 0.15 / 0.10 / 0.05 / 0 on a gradient gives five distinct results flattening
  to a uniform 128. That is why the Contrast slider is 0…2, symmetric about identity like Saturation
  beside it, rather than the suggested 0.25…4 which puts identity a fifth of the way along.
- `CIHighlightShadowAdjust.inputHighlightAmount`'s slider floor is **0.3** with identity **1**, at the
  range maximum — the control travels one way only, downward.
- `CIHighlightShadowAdjust` has a third parameter, `radius`, pixel-sized and a §5 violation if set.
  Default and identity are both **0**; `RenderPipeline` never touches it.
