# LUTzy — code review

_Full read of all 18 Swift files (~4,300 lines) at `094e932`, plus README, CI, and `PHASE2_SPEC.md`._

The app had grown across ten feature PRs with **no tests at all** — CI ran `swift build` and nothing
else at the time of this review; it now runs debug build → `swift test` → release build — so nothing
had ever been verified beyond "it compiles, and it looked right on the sample images in the repo." Those samples are all landscape, all 3:2, all from the same two cameras. Several of the
bugs below live exactly in the gap that leaves.

Findings are marked **[fixed]** where this pass resolved them and **[open]** where they are recorded for
later. Severity is about user impact, not effort.

---

## 1. Correctness

### B1 — EXIF orientation was ignored on every non-RAW image · High · [fixed]

`ImageProcessor.loadImage` decoded with `CIImage(contentsOf:)` and `AppViewModel.openImage(data:)` with
`CIImage(data:)`. **Neither applies the EXIF orientation tag.** But `CIRAWFilter` does, and so does the
thumbnail path (`kCGImageSourceCreateThumbnailWithTransform: true`, `ImageProcessor.swift:129`).

So for any portrait JPEG or HEIC:

- the preview showed it **on its side**,
- the filmstrip thumbnail beside it showed it **upright**,
- the status bar and inspector reported **swapped dimensions**,
- and the exported file was **written sideways**.

Measured on a JPEG with an 800×533 buffer and orientation tag 6:

| path | before | after |
|---|---|---|
| `loadImage(from: url)` | 800×533 ✗ | 533×800 ✓ |
| `loadImage(from: data)` | 800×533 ✗ | 533×800 ✓ |
| `generateThumbnail` | 160×240 ✓ | 160×240 ✓ |
| `ImageMetadata` | 800×533 ✗ | 533×800 ✓ |
| exported JPEG | 800×533 ✗ | 533×800 ✓ |

The same defect sat in `RecipeExtractor.derive`, where it was worse than cosmetic: a portrait JPG
compared against an upright RAW render meant the whole derivation was sampling unrelated pixels.

**Fix:** one shared `ImageProcessor.orientedLoadOptions` (`[.applyOrientationProperty: true]`) used by
every non-RAW decode, plus orientation-aware dimensions in `ImageMetadata`.

### B2 — Decode and preview rasterization ran on the main actor · High · [fixed]

`applyLUT`'s `previewTask = Task { … }` inherited `@MainActor` from the view model, so
`renderPreview` → `context.createCGImage` blocked the main thread. `openImage`'s `Task { … }` ran the
full RAW demosaic there too. And because the task body contained no suspension point, the
`Task.isCancelled` check could never interrupt a render already underway — cancellation only skipped
renders that hadn't started, so a slider drag queued one full render per tick.

The README claimed "Responsive by design… LUT application is cancellable." `PHASE2_SPEC.md` had
independently flagged the same thing as "a confirmed responsiveness bug."

**Fix:** the filter graph is still assembled on the main actor (Core Image is lazy — that part is nearly
free), but rasterization moved to `Task.detached` with the result published back. Preview rendering is
now a single funnel (`schedulePreview`) instead of three call sites that each wrote `previewNSImage`,
and `setLUTIntensity` debounces at 60 ms.

### B3 — Launch blocked on disk I/O · Medium · [fixed]

`LUTLibrary.scan` parsed every `.cube` synchronously on the main actor — a 33³ LUT is ~36k lines of text
to parse, and the bundled library has 33 of them. `AppViewModel.init` then chained `restoreFolder()` →
`restoreSourceFolder()` → recursive folder enumeration → `openImage` on the first file, all on the main
actor before the window could paint.

**Fix:** both scans run detached and publish finished results; `AppViewModel.init` kicks them off and
returns. Callers that need `items` (open the first image) await `collection.scanCompletion()` rather
than reading it synchronously. The sidebar shows a scanning state while the LUT scan is in flight.

### B4 — The reported "Sharpening" ratio was meaningless · Medium · [fixed]

`jpgHFEnergy` accumulated over **every** random draw, edges included, as |jpg − blurred|².
`rawHFEnergy` accumulated only over **accepted smooth samples**, as a horizontal neighbour difference².
Two different operators over two different pixel sets of two different sizes — the quotient was not a
ratio of anything.

On the `realworldtest` Leica pair it reported **0.542×**, i.e. that the in-camera JPEG was *less* sharp
than the neutral RAW render. In-camera JPEGs are sharpened; the number was not merely imprecise, it
pointed the wrong way.

**Fix:** both energies now use the same operator (squared horizontal neighbour difference) at the same
aligned pixel over the same draws — edges included, since that is where sharpening lives. Same pair now
reports **1.165×**.

### B5 — RAW/JPG geometry was never validated · Medium · [fixed]

`lanczosScale` forced the RAW onto the JPG's extent with independent X and Y scale factors. A mismatched
pair — an in-camera crop mode, a rotated JPG, or simply the wrong file picked in the sheet — was
silently stretched, and produced a garbage cube behind a report card that looked entirely plausible.

**Fix:** aspect ratios are compared up front (1% tolerance) and a mismatch throws
`ExtractorError.geometryMismatch` naming both dimensions. Verified: a 4928×3288 RAW against a 533×800
JPG is now rejected with a readable message instead of deriving.

### B6 — Derive was uncancellable and allocated at full resolution · Medium · [fixed]

Three full-resolution RGBA8 buffers (raw + jpg + blurred) were held simultaneously, and no stage polled
for cancellation, so closing the sheet left the work running.

**Fix:** the pair is analyzed at a working resolution (3000 px long edge by default, `Options.workingLongEdge`)
— sampling is statistical, so 200k samples describe the mapping just as well — and an `isCancelled` hook
is polled between stages and inside the sample loop. `dismissRecipeExtractor` cancels an in-flight run.

Measured on the 16 MP `realworldtest` pair: peak RSS **403 MB → 238 MB**, with coverage effectively
unchanged (2.8% → 2.5%) and saturation within noise (1.095× → 1.076×). The gap widens sharply with
sensor size — a 60 MP pair was allocating roughly 700 MB in buffers alone.

### B7 — Stale bookmarks discarded; security scope never released · Low · [fixed]

`LUTLibrary.restoreFolder` and `ImageCollection.restoreSourceFolder` both declared `isStale` and threw
it away, so once a bookmark went stale the folder silently stopped persisting across launches.
`startAccessingSecurityScopedResource()` had no matching `stopAccessing…`.

**Fix:** a stale bookmark is re-minted while access is held; the scoped URL is tracked and released in
`deinit` and when superseded.

### B8 — `render()` was declared failable but could not fail · Low · [fixed]

`CIContext.render(toBitmap:)` returns `Void`, so `ExtractorError.renderFailed` was unreachable and a bad
image yielded a silently all-black buffer that the sampler would then happily analyze. Now guards the
destination and the image extent.

### B9 — Dead filter construction in `boxBlur` · Low · [fixed]

Built a `CIFilter.boxBlur()`, set its `inputImage` and `radius`, then discarded it and returned
`image.clampedToExtent().applyingFilter("CIBoxBlur", …)`. Removed. Also removed the leftover
`_ = sampleCount` / `_ = cubeCells` no-op statements from `derive`.

### B10 — ⌘S was bound twice · Low · [fixed]

Both the File ▸ Export menu item and the toolbar Export button declared `.keyboardShortcut("s")`.
Dropped from the toolbar button (which keeps a `.help` mentioning the shortcut).

### B11 — A thumbnail could land on the wrong row · Low · [fixed]

`generateThumbnails` re-checked that index `i` still existed but not that `items[i]` was still the same
file, so a refresh that reordered the list mid-flight could attach a thumbnail to a different image. Now
matches on the item's `id`.

### B12 — Divide-by-zero on a degenerate LUT domain · Low · [fixed]

`CubeLUT.init(url:)` computed `scale = domainMax - domainMin` unguarded; a `.cube` with equal bounds on
any axis filled the whole table with NaN. Such an axis now falls back to the default 0…1 range.

### B13 — A single-image folder was inert · Low · [fixed]

`isActive = items.count > 1` meant a folder holding exactly one image left `selectedItem` nil and ←/→
dead, while the browser panel still listed the row. Now `!items.isEmpty`.

### B14 — `InfoInspectorView`'s histogram label still assumes a LUT · Low · [open]

`InfoInspectorView.swift:105` derives its "Graded"/"Original" histogram label from
`viewModel.selectedLUT != nil` — the same root cause as `PreviewView`'s split-view label, which read
`selectedLUT?.name ?? "LUT"`. Phase 2 Step 10b's Adjust panel made both stale the same way:
`isComparisonAvailable` now also goes true for an adjustment-only edit with no LUT selected, so this
panel still calls that render "Original" while a real, non-identity edit is showing. `PreviewView`'s
equivalent was fixed in Step 10b's follow-up pass (the fallback now reads "Adjusted"); this is the
one remaining site, deliberately deferred out of that pass's scope.

### B15 — A failed open during the RAW probe parks the Develop panel on "probing" forever · Low · [open]

`AppViewModel.load` cancels `capabilitiesTask` unconditionally at `:375`, before it knows whether the
new file decodes. `refreshCapabilities()` (`:799`) — which clears `rawCapabilities` and starts a fresh
probe — is reached only from the `.success` branch, at `:427`. The `.failure` branch and the
`guard !Task.isCancelled` early return both skip it.

So: open a RAW, then within the 25–170 ms probe window step onto a file that fails to decode. The
first image's probe is killed and never restarted, while `sourceImage` and `imageSource` still describe
that first image. `rawCapabilities == nil` with `sourceIsRAW == true` is exactly `developPanelState`'s
`.probing` case, so the panel spins on "Reading the decoder's develop controls…" indefinitely, beside
the RAW that is still on screen. Recovered by opening any image that decodes.

Narrow, but reachable and unbounded. Found by the opposition pass while checking the doc comment on
`developPanelState`, which claimed the clear happens "on every open".

**Why no test caught it:** every `developPanelState` test builds a fresh `AppViewModel` and opens
exactly one image (`DevelopInspectorTests.swift:40-199`). Nothing opens a second image over an
in-flight probe, so the whole class of stale-state-across-opens defects is uncovered.

**Adjacent, same function, also [open]:** `refreshMetadata(url:data:)` (`:781`, called at `:426`) fires
an *unstored, uncancelled* `Task.detached` that writes `self.metadata` on the main actor — unlike the
six tasks cancelled at `:371-376`, there is no stored handle to cancel and no generation token. Rapid
←/→ can therefore land image A's `ImageMetadata` after image B's has already been published, leaving
the Info panel describing the wrong file. Same root shape as B11.

---

## 2. Stubbed, incomplete, and dead

**[open]** unless noted.

- ~~**No tests, anywhere.**~~ **[fixed]** — the package is now split into `LUTzyKit` plus a thin `@main`
  executable, with 61 XCTest cases and `swift test` wired into CI. Fixtures are generated, never
  committed. Coverage is deliberately concentrated where the review found real defects: the `.cube`
  parser, the orientation load path, cube assembly, the async scans, and export naming.

  Each regression test was mutation-checked — the fix was reverted and the suite confirmed to fail —
  so the coverage is known to bite rather than merely to exist. Two tests were too weak on the first
  pass and were tightened after the mutation run: the degenerate-domain test was asserting on rendered
  output (Core Image clamps NaN to 0, so a fully corrupt table still rendered "valid" pixels) and now
  inspects the parsed table directly; the missing-folder test asserted only that *some* error appeared,
  which the empty-folder message also satisfied.

  Phase 2 Step 2 added a third variety of the same weakness, worth naming because it will recur
  wherever a test drives a framework object: **asserting a value that was already the default.**
  `RAWDevelopSettings`' round-trip test set `lensCorrectionEnabled` and `highlightRecoveryEnabled` to
  `true` and asserted `true` — but `CIRAWFilter` defaults both to `true`, so both assertions passed
  just as happily against an `apply(to:)` that skipped them entirely. A mutation check caught it; the
  fix is to write a value that *departs* from the decoder default. When a test writes to a framework
  object, print the defaults for the fixture first and check that each written value actually differs.

  Writing them turned up one further bug: **`ImageProcessor.histogram(of:)` trapped on an
  infinite-extent image.** `CGRect.infinite` is built from `greatestFiniteMagnitude`, not `inf`, so the
  existing `isFinite` guard passed and `Int(rect.width)` then crashed. Not reachable from today's UI —
  every image in the app comes from a decoder — but one filter change away, and `renderPreview` and
  `export` shared the pattern. All three now go through `CGRect.isRasterizable`.
- `LUTLibrary.scanError` was set but no view ever read it, so folder-scan failures were silent.
  **[fixed]** — the sidebar now shows it.
- `RecipeReport.alignmentShift` is computed, stored, and documented, but `RecipeReportView` never renders
  it. Either show it (it is the one number that tells you the pair was mis-registered) or drop it.
- `RecipeExtractor.Options` — cube size, sample counts, edge threshold, search radius, and now working
  resolution — has no UI. Cube size is effectively hardcoded at 33.
- Unused API: `ImageMetadata.hasCameraInfo`, `ImageMetadata.isEmpty`, `ImageCollection.selectedItem`,
  `HistogramData.Channel: CaseIterable`. **[partly fixed]** — `ImageProcessor.renderToNSImage` was on
  this list and went with the rest of the type in Phase 2 Step 7, along with `renderPreview`,
  `export` and `histogram`, all of which the engine now owns.
- `dismissRecipeExtractor` claimed the scratch `.cube` was "cleared … on app exit". Nothing cleared it.
  **[partly fixed]** — a cancelled derive no longer writes one; a completed one is still kept
  deliberately (so the sheet can be reopened) and left to the OS temp sweep. **Phase 2 Step 9 did not
  change this**, deliberately: it changed what *names* a derived LUT (a content hash, no longer the
  temp path) and left the file bookkeeping exactly as it was. Still `[partly fixed]`.
- **A derived LUT never resolved, so a successful derive showed an ungraded preview.** **[fixed]** in
  Phase 2 Step 9 — `derive` named its result after the scratch temp file, so `LUTID.isDerived` read
  false and resolution fell through to a library lookup for a path no library contains. Measured
  before the fix: preview delta versus ungraded was **0/255**.

  Worth recording for the pattern rather than the bug: **two tests covered this and both were green**,
  because both built their fixture with `CubeLUT(cube:size:name:)` — no `sourceURL`, hence a
  `derived://` id — where production produced a path. A fixture that differs from production *in the
  field under test* is the "wrote a value that equals the default" weakness one level up, and it is
  the fourth variety this repo has shipped. The fix is structural, not a patched assertion:
  `DeriveCoordinator.makeDerivedLUT` is now the only constructor, used by production and every test,
  so the fixture cannot drift again.
- `RenderEngine.invalidateLUTCache()` existed and was tested, but **the app never called it** — the
  only caller was a test. **[fixed]** in Step 9, which also made it reachable: saving a second derive
  over the same `.cube` path yields the same `LUTID`, so the cache would serve the first cube forever.
  It is on the `RenderEngining` protocol now (so the app calling it is assertable from above the
  actor) and fires from a `LUTLibrary.onScanned` closure covering every scan. Measured: without the
  flush, a replaced cube renders **0/255** different from the one it replaced.
- Export quality is hardcoded at 0.95 with no UI, and no EXIF/ICC metadata survives an export. Note that
  metadata cannot be injected through `CIImageRepresentationOption` — it needs `CGImageDestination`.
- Phase 2 — non-destructive pipeline, RAW develop controls, undo, per-image edits — was unbuilt at the
  time of this review. **[partly fixed]** since: Steps 0–10b shipped the first two. `EditDocument` is
  the look state, `RenderPipeline`/`RenderEngine` render the preview and both export paths from it,
  `ImageProcessor` and its baked `processedImage` are gone (zero declarations and zero call sites at
  HEAD), and both inspectors ship — RAW develop in Step 10a, Adjustments in Step 10b. The A/B
  comparison is the load-bearing evidence for "non-destructive": `AppViewModel` re-renders two looks
  from one untouched `ImageSource` with no reload, which a baked pipeline could not serve.
  **Undo and per-image edits remain open**, deferred to Step 11's `EditDocumentStore`.

---

## 3. Organization

**[open]** — deliberately not touched in this pass, to keep the correctness diff reviewable.

- ~~**`AppViewModel` (674 lines) is a god object**~~ **[fixed]** — split into `ExportCoordinator`
  (single + batch export and the naming they share, including `uniqueExportURL`) and `DeriveCoordinator`
  (derive / save / scratch lifecycle). `AppViewModel` drops to ~516 lines holding image, LUT, preview,
  and histogram state, and wires the coordinators' `onStatus`/`onError` closures to the status bar and
  alert — they report *what* happened, it decides how that is shown.

  The split was chosen to buy testability, not tidiness: every panel-driven operation is now a
  `perform…` core taking an explicit URL plus a thin `…Dialog` wrapper, so export and save can run
  headless. That is what the 34 new tests in `ExportCoordinatorTests`, `DeriveCoordinatorTests`, and
  `AppViewModelTests` stand on.
- ~~**`ContentView.swift` holds several unrelated top-level types.**~~ **[fixed]** — the menu commands
  and `MenuCommandReceivers` moved to `MenuCommands.swift`, `StatusBar`/`KeyHint` to `StatusBar.swift`,
  and `KeyboardShortcuts`/`KeyMonitor` to `KeyboardShortcuts.swift`. `ContentView.swift` is down to
  ~231 lines: the layout and the toolbar, nothing else.
- `HistogramChart` lives at the bottom of `InfoInspectorView.swift`, away from `Histogram.swift`.
- **`docs/PHASE2_SPEC.md` is 4,180 lines** of raw multi-agent output. It contradicts itself across
  sections, and a meaningful fraction of it is meta-commentary arguing with earlier drafts about bugs
  that never existed ("FABRICATED PRE-EXISTING BUG (verified false)"). Its actual decisions — the
  `EditDocument` value spine, the `RenderPipeline.buildImage` fold, the `actor RenderEngine`, the
  `WorkingSpace` seam — would fit in under 300 lines. As it stands it is more likely to mislead an
  implementer than guide one.
- `.gitignore` claimed "Package.resolved is intentionally committed" for a project with zero
  dependencies and no `Package.resolved`. **[fixed]**

---

## 4. README drift

All **[fixed]**. Worth noting how it drifted: the in-app status bar hints were *correct* the whole time,
so the README was the only wrong copy of the keymap.

- The shortcut table said `←`/`→` cycled LUTs and `[`/`]` cycled images. The code binds ↑/↓ to LUTs and
  both `←`/`→` and `[`/`]` to images.
- Shipped but undocumented: the intensity slider, the Info inspector (⌘I), the source-folder browser
  (⌘⌥I) and its refresh (⌘R), and Export All (⌘⇧E).
- The project-structure tree omitted four files: `Models/Histogram.swift`, `Models/ImageMetadata.swift`,
  `Views/InfoInspectorView.swift`, `Views/SourceBrowserView.swift`.
- "Responsive by design… LUT application is cancellable" described an intention, not the code (B2).

---

## 4b. In-app copy drift · [open]

Found by the opposition pass, which harvested claims from documentation and doc comments but not from
the strings the app actually shows. Every item below is verified against HEAD. **None is a correctness
bug** — they are all cases where shipped copy describes an older, smaller app — but they are the copy a
user reads, which makes them worse than a stale spec line, not better.

Left open rather than fixed, because each is a wording decision rather than a mechanical correction.

- `ContentView.swift:224` — Export All's tooltip reads "Apply the current **LUT** to all imported
  images". `ExportCoordinator.performBatchExport` takes an `EditDocument`, so it applies the whole
  look — `rawDevelop` and `adjustments` included — to every image in the folder. This is the shipped-UI
  twin of the README drift fixed above, and it is the more consequential one: the document's
  `rawDevelop` was seeded from *one* RAW's as-shot values, and the tooltip gives no hint that those
  travel to every other file.
- `ContentView.swift:149` ("Show histogram & EXIF (⌘I)") and `InfoInspectorView.swift:157` ("Open an
  image to see its histogram and EXIF data") — the inspector has been a three-tab Info/Develop/Adjust
  picker since Step 10b. Both strings name only the first tab.
- `RecipeReportView.swift:107` — the Sharpening badge's hint reads "applied separately, not in LUT".
  Nothing applies it: `sharpeningRatio` is measured (`RecipeExtractor`), carried (`RecipeReport`), and
  displayed, and has no consumer anywhere in the render path. "Measured, not applied" would be true.
- `RecipeExtractor.swift:78` — `geometryMismatch`'s message says the two files "must be the same frame
  at the same aspect ratio", but the guard at `:159` compares aspect only, within
  `aspectTolerance = 0.01`. Differing pixel dimensions are accepted by design (that is what the Lanczos
  step exists for), so the message overstates the requirement it is explaining.

**Also open, same class:** Step 10b's ship gate in
`docs/superpowers/plans/2026-08-06-step10b-adjustments-inspector.md` — `git diff --stat` over four
files, "Expected: **no output**" — would have failed on the merge that shipped it. Re-run against the
merge base, `AdjustmentNode.swift` and `RenderPipeline.swift` both moved. **The design intent held**:
every changed line is a doc comment, and the changes are the §8.7 closures. The defect is in the gate,
which cannot tell a comment from a statement. A gate that means "no logic changed" has to diff code,
not lines.

---

## 5. Suggested order for the follow-up work

1. ~~**`LUTzyKit` split + test target.**~~ **Done** — see §2.
2. ~~**Split `AppViewModel` and the rest of `ContentView`.**~~ **Done** — see §3.
3. ~~**Distil `PHASE2_SPEC.md`**~~ **Done** — 292 lines, §6 of it is the ordered migration.

**Phase 2 itself is now the only work left.** Steps 0–2 of its migration are complete: the library
split and test harness, the `WorkingSpace` colour seam (which closed the latent preview/export
mismatch — `createCGImage` passed no colour space in two places), and the value-state types
(`EditDocument` and friends), which are defined but not yet referenced by anything. Step 3, the
`RenderPipeline`, is next.

### Where coverage is still thin

Worth knowing before leaning on the suite:

- **The panels themselves are untested**, and can't be — `NSOpenPanel`/`NSSavePanel` need a UI session.
  Everything behind them now is tested; what is not covered is that the wrapper passes the panel's URL
  to the core, which is a two-line body in each case.
- **`RecipeExtractor.derive` end-to-end is tested only where a RAW exists.** Phase 2 Step 9 added
  `DeriveInvarianceTests`, which runs a real derive on the `realworldtest` (DNG, in-camera JPG) pair
  and checks the cube lands the same way through the new pipeline as it does over
  `developRAWNeutral`. **It skips on CI**, which has no DNG — read the green tick there as saying
  nothing about derive. The pure pieces (`buildCube`, `workingSize`, the error messages) are covered
  everywhere; alignment and the sample loop are covered locally only. A small synthetic DNG remains
  the only way to close that, and is still not worth the effort of generating one.
- **No SwiftUI view tests.** Views are exercised only insofar as the view model is.
- **The `CIRAWFilter` half of `RAWDevelopSettings` only runs where a RAW exists.** Several tests build
  a real filter from `Fixtures.localRAWURL` — the untracked `realworldtest/` DNG — and `XCTSkip` when
  there is none, which includes CI. The value semantics are covered everywhere; the framework wiring
  is covered only locally.

  This entry used to claim the `is*Supported` gates "are not covered at all: that needs a RAW whose
  decoder *lacks* an adjustment, and the Leica file supports every one of them." **Measured in Phase 2
  Step 10a, the second half of that is wrong** — `isLocalToneMapSupported` is `false` on that file, so
  there was a gated branch to aim at all along.

  What replaced it, stated exactly. The `is*Supported` gates in `apply(to:)` are covered two ways: a
  real-pixel test on the Leica DNG in `realworldtest/` shows that writing a value for an unsupported
  adjustment changes nothing end to end (because `CIRAWFilter` itself silently discards the write,
  independent of our own gate — measured worst pixel delta: 0), and a source-text test
  (`RAWDevelopSettingsTests.testEveryGatedAdjustmentIsAppliedOnlyBehindItsOwnSupportedFlag`)
  independently checks that each of the **nine** gated properties in `apply(to:)` is written inside a
  condition that **names** its own `is*Supported` flag, which is the part the pixel test cannot see:
  the eight per-file adjustments from a table, and `highlightRecoveryEnabled` separately and more
  strictly, for its `#available(macOS 26, *)` guard as well as its flag.

  (This said "eight" until the opposition pass. Eight is the count of gated *seeds* on
  `RAWCapabilities` — highlight recovery has no per-image seed — so it is right for seeds and wrong
  for gated writes; the repo says nine everywhere else. The error was in the safe direction, since it
  undersold a test that does cover the ninth. It was introduced the day *after* the ninth gate landed,
  and survived a later rewrite of this very paragraph.)

  **That is deliberately narrower than "verifies the gate holds", and the entry should not round it
  up.** The test reads the source of `apply(to:)` and asserts each write's condition mentions the
  right flag; it says nothing about what the condition then does with it. As its own doc comment puts
  it, a rewrite that keeps the flag but inverts the check would slip through. It is a guard against
  **deletion** — the failure that actually happens to a line like that — and the whole point of
  rewriting this entry was to state coverage exactly rather than approximately.

  Two patterns worth carrying forward. The original claim was plausible, went unchecked for several
  steps, and cost nothing to disprove once someone printed the flags. And the obvious replacement —
  "the pixel test covers it now" — would have been the same mistake a second time: removing the gate
  from `apply(to:)` leaves that test green, because the framework's own discard absorbs the write. A
  test that passes either way is not coverage, however real its pixels are.
