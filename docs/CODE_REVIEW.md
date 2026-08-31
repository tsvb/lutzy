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

**Fix:** one shared `orientedLoadOptions` (`[.applyOrientationProperty: true]`) — on `ImageProcessor`
at the time, on `ImageDecoder` since Step 7 dissolved that type — used by
every non-RAW decode, plus orientation-aware dimensions in `ImageMetadata`.

### B2 — Decode and preview rasterization ran on the main actor · High · [fixed]

`applyLUT`'s `previewTask = Task { … }` inherited `@MainActor` from the view model, so
`renderPreview` → `context.createCGImage` blocked the main thread. `openImage`'s `Task { … }` ran the
full RAW demosaic there too. And because the task body contained no suspension point, the
`Task.isCancelled` check could never interrupt a render already underway — cancellation only skipped
renders that hadn't started, so a slider drag queued one full render per tick.

The README claimed "Responsive by design… LUT application is cancellable." `PHASE2_SPEC.md` had
independently flagged the same thing as "a confirmed responsiveness bug."

**Fix:** rasterization moved off the main actor — as shipped then, into a `Task.detached`, while the
lazy filter graph was still assembled on the main actor (Core Image is lazy, so that part is nearly
free). Preview rendering became a single funnel (`schedulePreview`) instead of three call sites that
each wrote `previewNSImage`, and `setLUTIntensity` debounces at 60 ms.

**Superseded, both halves, by Phase 2 Step 5** — noted here rather than rewritten, following this
file's convention. Graph assembly *and* rasterization now live inside `actor RenderEngine`, so
`schedulePreview` is a plain `Task` (not detached) that hands only `Sendable` values across the actor
boundary, and the main actor builds no filter graph at all — what keeps `createCGImage` off it is the
actor hop, not the task type. The funnel and the 60 ms debounce are unchanged and still accurate.

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

### B14 — `InfoInspectorView`'s histogram label assumed a LUT · Low · [fixed]

`InfoInspectorView` derived its "Graded"/"Original" histogram label from `viewModel.selectedLUT != nil`
— the same root cause as `PreviewView`'s split-view label, which read `selectedLUT?.name ?? "LUT"`.
Phase 2 Step 10b's Adjust panel made both stale the same way: `isComparisonAvailable` also goes true
for an adjustment-only edit with no LUT selected, so this panel called that render "Original" while a
real, non-identity edit was showing. `PreviewView`'s equivalent was fixed in Step 10b's follow-up pass
(the fallback reads "Adjusted"); this was the one remaining site.

**Fix:** `AppViewModel.histogramSource`, a three-case enum derived beside `isComparisonAvailable` and
read by the view. Put in the view model rather than the `ViewBuilder` for the reason `developPanelState`
gives — this repo has no SwiftUI view tests, so a distinction living only in a view cannot be asserted,
and this one had already been wrong once.

Written in terms of the same predicates as the A/B gate rather than in terms of `selectedLUT`, which
makes it exact at two edges the old label could not have reached: a LUT at **zero intensity** is
`lut.isIdentity`, so it reads "Adjusted" beside real adjustments and "Original" on its own; and
`rawDevelop` is deliberately not consulted, matching `originalForComparison`, so a develop-only edit
reads "Original" because both sides of the comparison genuinely show the same histogram. All seven
look states are pinned as a table in `AdjustInspectorTests.testTheHistogramCaptionOverEveryLookState`.

### B15 — A failed open during the RAW probe parked the Develop panel on "probing" forever · Low · [fixed]

`AppViewModel.load` cancelled `capabilitiesTask` unconditionally, before it knew whether the new file
decodes, while `refreshCapabilities()` — which clears `rawCapabilities` and starts a fresh probe — is
reached only from the `.success` branch. The `.failure` branch and the `guard !Task.isCancelled` early
return both skip it.

So: open a RAW, then within the 25–170 ms probe window step onto a file that fails to decode. The
first image's probe is killed and never restarted, while `sourceImage` and `imageSource` still describe
that first image. `rawCapabilities == nil` with `sourceIsRAW == true` is exactly `developPanelState`'s
`.probing` case, so the panel spun on "Reading the decoder's develop controls…" indefinitely, beside
the RAW that is still on screen. Recovered only by opening an image that decodes.

Narrow, but reachable and unbounded. Found by the opposition pass while checking the doc comment on
`developPanelState`, which claimed the clear happens "on every open".

**Fix — cancel at the refresh site, not the load site.** `load()` no longer cancels the probe;
`refreshCapabilities()` already did, and it is the only place that knows a replacement is actually
coming. On a successful open that runs in the same main-actor turn as the decode, so the behaviour is
unchanged; on a failed one the probe finishes and describes the image the user is still looking at.
At most one probe's *answer* is ever published — the superseded task's `Task.isCancelled` guard
discards it — but two probe tasks can be alive at once. Cancelling the handle cannot resume a task
already suspended inside `rawCapabilities(for:)`, and the guard sits after that `await`. **This
sentence originally read "at most one probe is ever in flight, because there is only one handle to
hold it", which is false**, and it was written by the pass that fixed B15. One handle bounds how many
tasks you can still cancel, not how many are unfinished; `LoadCancellationTests` reaches a
`capabilityProbeCount` of 2 by design.

**Why no test caught it:** every `developPanelState` test built a fresh `AppViewModel` and opened
exactly one image. Nothing opened a second image over an in-flight probe, so the whole class of
stale-state-across-opens defects was uncovered. `LoadCancellationTests` opens two, and includes the
converse — a *successful* open must still supersede the previous probe's answer, or "stop cancelling"
would be satisfiable by never cancelling.

**Adjacent, same function, also [fixed]:** `refreshMetadata(url:data:)` fired an *unstored,
uncancelled* `Task.detached` that writes `self.metadata` on the main actor — no handle to cancel and no
generation token, so image A's `ImageMetadata` could land after image B's had been published and leave
the Info panel describing the wrong file. Same root shape as B11. Now stored, cancelled by the call it
supersedes, and checked for cancellation before publishing.

That one is pinned **as source text**, and the entry should not round it up: `ImageMetadata.read` is a
static call with no injection seam, so no test can hold one read open while another finishes. The
honest options were a timing-dependent test that would flake or a structural one, and the structural
one catches deletion — the failure that actually happens to lines like these — while proving nothing
about the ordering itself.

### B16 — `CIRAWFilter` accepts garbage, so an undecodable RAW opened at 0×0 · Low · [fixed]

Found while building B15's fixture, which needed a file that fails to open.

`ImageDecoder.load` guarded the RAW branch with a `nil` check, as though `CIRAWFilter` behaved like
`CIImage(contentsOf:)`. It does not. Measured: handed **twelve bytes of ASCII text** named `.dng`,
`CIRAWFilter(imageURL:)` constructs a filter *and* returns an `outputImage`, with extent
`(inf, inf, 0.0, 0.0)`. Nothing was `nil`, so the decoder returned it as a valid image.

The result was quiet rather than loud, because the render paths guard on `isRasterizable` downstream
(§1, `CGRect.isRasterizable`): a corrupt, truncated, or simply misnamed RAW "opened", the status bar
read `0×0`, the preview stayed blank, and no error was ever shown. The non-RAW branch never had this
hole.

**Fix:** the RAW branch checks `output.extent.isRasterizable` as well as `nil` — the guard the module
already had, applied at the decode boundary rather than only downstream of it. Third instance of the
same shape in this review: a framework accepting input the code assumed it would reject (B1
orientation, B12 degenerate LUT domain). Covered on CI — the fixture is a text file, not a RAW — with
the converse pinned too, so the fix is not satisfiable by rejecting every RAW.

### B17 — Ten of the Step 10a harness's 36 mutants had been inert for three weeks · Medium · [fixed]

Not an app defect — a defect in the thing that proves the app's tests bite, which is worse in one
specific way: it is the instrument, and a broken instrument makes every reading it took unreliable.

`scripts/mutate-step10a.sh:125` sets `VM=…/AppViewModel.swift`. `0b7c9bc` ("Split the develop bindings
out of AppViewModel") moved `developValue(for:)`, the seed fall-throughs, the tint binding,
`resetDevelop` and the toggle/slider debounce split into `AppViewModel+Develop.swift` — **the day after
this harness was written**. `$VM` was never repointed.

Measured by dry-run substitution over all 36 mutations (apply each perl expression, compare bytes):
**10 matched nothing.** Each hits the NO-OP branch, increments `NORUN`, and fails the gate. The split
is clean — 11 mutations match only `AppViewModel.swift`, 10 only `AppViewModel+Develop.swift`, zero
overlap — so repointing `$VM` wholesale would have killed the other 11 exactly as this killed these.
Fixed by adding `$VMD` and repointing precisely those ten.

What was lost is reproducibility: nothing at HEAD proved `DevelopInspectorTests` would fail if the
seed fall-throughs or the toggle/slider debounce split broke. **Measured after the fix, on an
untouched run: 35 caught, 0 SURVIVED, 0 NO-BUILD, 0 NO-TESTS, 0 SKIPPED — exit 0.** That is the first
time this harness has ever exited 0; it has been failing on dead anchors since Step 10b, and every
one of the ten repointed mutants is caught.

Two earlier runs reported one SURVIVED and were both wrong, in the same way and for the same reason:
other commands were running. `--check` and the sibling harness mutate tracked sources through the
*same* `$file.bak` path, and a concurrent `swift build`/`swift test` contends for `.build`. Re-running
the flagged mutation alone showed `testWritingAToggleThroughTheBindingSkipsTheDebounce` failing with a
precise message both times. Both scripts now say to run them alone, and to treat a SURVIVED as a
hypothesis to re-check by hand — **"N failures" is not evidence that the intended test failed**, which
is the same reasoning error this review keeps finding in the repo's own record.

**This is the sharpest self-indictment in the file.** The failure was *loud*: ten NO-OP lines and a
non-zero exit, every run, for three weeks. Nobody saw it because nothing runs these harnesses — no CI
job, no ship gate, one comment referencing them — and because PR #28 armed this script's exit gate,
arguing at length that "an exit code that is always 1 says nothing", **without ever running it.** It
verified the sibling harness and assumed the shared classifier meant a shared fate.

The general shape: **a path in a script is a string, and code motion is invisible to it.** The other
findings in this pass are prose drifting from code; this one is tooling drifting from code, and it is
the only kind that quietly weakens everything downstream.

**Two things were hiding behind the dead path**, and repointing surfaced both:

- One mutation no longer compiles — `"reading a control writes the seed"` assigns to
  `document.rawDevelop`, and `document` is `@Published private(set)`, so its setter is file-private
  and `AppViewModel+Develop.swift` cannot write it. **That is the compiler enforcing the property
  outright**, which is stronger than any mutation could demonstrate, so the mutation is retired with a
  note rather than rewritten into a compiling variant.
- The clean split is 11 mutations anchored in `AppViewModel.swift` and 10 in
  `AppViewModel+Develop.swift`, zero overlap — so the obvious fix of repointing `$VM` wholesale would
  have killed the other 11 exactly as this killed these. Measured before choosing.

**The guard: `scripts/mutate-*.sh --check`.** It dry-runs every mutation's anchor — apply the
substitution, compare bytes — and exits non-zero on any NO-OP, without building anything. It runs in
**0.4 seconds**, needs no DNG and no toolchain beyond perl, and reverting this fix makes it report the
nine dead anchors and exit 1. It would have caught B17 in the commit that caused it.

Anchoring is the part that rots and the part that is free to test; whether the tests actually catch a
mutation still costs a full run. A green `--check` says only that the mutations still describe this
codebase — which is precisely the claim that was silently false for three weeks.

---

## 2. Stubbed, incomplete, and dead

**[open]** unless noted. What is genuinely still open here is **feature work, not drift**: no UI for
`RecipeExtractor.Options` (cube size is effectively hardcoded at 33), export quality hardcoded at 0.95
with no EXIF/ICC survival, and Phase 2's undo and per-image edits, which are Step 11. Everything in
this section that was a *defect* or a *stale claim* is marked fixed below.

- ~~**No tests, anywhere.**~~ **[fixed]** — the package is now split into `LUTzyKit` plus a thin `@main`
  executable, with `swift test` wired into CI. The split landed **61** XCTest cases; the suite stands
  at **322** across 32 test classes at HEAD (22 skip without a DNG, 3 with one present). Fixtures are generated, never
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
- `RecipeReport.alignmentShift` was computed, stored, and documented, but `RecipeReportView` never
  rendered it. **[fixed]** — shown, as the review preferred. Of everything on that report it is the one
  number that says the *pair* was wrong rather than the fit: every other stat stays plausible under a
  mis-registered pair, because the cube still fits, just to the wrong pixels. It reads "aligned" at
  (0, 0) — the expected result — and turns yellow with a hint beyond ±1 px, one pixel of play because
  the search is integer-pixel and a ±1 result on a real pair is rounding, not a crop difference.
- `RecipeExtractor.Options` — cube size, sample counts, edge threshold, search radius, and now working
  resolution — has no UI. Cube size is effectively hardcoded at 33.
- Unused API. **[fixed]**, and one entry was wrong. `ImageMetadata.hasCameraInfo`,
  `ImageMetadata.isEmpty` and `HistogramData.Channel`'s `CaseIterable` conformance had no caller in
  either target and are removed — `InfoInspectorView` asks `metadata.sections.isEmpty` directly, which
  is the same question one indirection shorter, and the histogram picker iterates
  `HistogramChart.Mode`, a different type with an `rgb` case `Channel` has no equivalent for.
  **`ImageCollection.selectedItem` was listed here in error**: `LibraryScanTests` has covered it since
  the scan work, in the test that pins the defect where a stalled scan left `isActive` false and killed
  ←/→. It stays. `ImageProcessor.renderToNSImage` was also on this list and went with the rest of the
  type in Phase 2 Step 7, along with `renderPreview`, `export` and `histogram`, all of which the engine
  now owns.
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

**[fixed]** — every bullet below is now closed. It was deliberately not touched in the original
pass, to keep the correctness diff reviewable; the work landed across Steps 7–10b and the
review-alignment pass.

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
- ~~`HistogramChart` lives at the bottom of `InfoInspectorView.swift`, away from `Histogram.swift`.~~
  **[fixed]** — it is `Views/HistogramChart.swift` now. Moved there rather than into
  `Models/Histogram.swift` as this bullet suggested: that file is the *data*, and the Models layer does
  not import SwiftUI. Keeping the tally and the drawing in separate layers is why the histogram is
  testable without a view at all.
- ~~**`docs/PHASE2_SPEC.md` is 4,180 lines** of raw multi-agent output, self-contradicting, a
  meaningful fraction of it meta-commentary arguing with earlier drafts about bugs that never existed
  ("FABRICATED PRE-EXISTING BUG (verified false)").~~ **[fixed]** — distilled at the time (§5 item 3),
  and this bullet simply outlived the fix. Measured at `aa86580`: **534 lines, zero occurrences of
  "FABRICATED"** (the file is edited by most correction waves, so treat the line count as a snapshot
  with a date on it, not a fact — that is the same failure mode as the 4,180 it replaced, with a
  shorter fuse; `wc -l docs/PHASE2_SPEC.md` is the only trustworthy answer). It has grown past the 292 it was distilled to, because Steps 3–10b each recorded
  what they measured, which is the point of it.
- `.gitignore` claimed "Package.resolved is intentionally committed" for a project with zero
  dependencies and no `Package.resolved`. **[fixed]**

---

## 4. README drift

The four below were fixed at the time. **The README then went 71 commits without an edit**, and a
second wave of drift is recorded at the bottom of this section. Worth noting how the first wave
drifted: the in-app status bar hints were *correct* the whole time, so the README was the only wrong
copy of the keymap.

- The shortcut table said `←`/`→` cycled LUTs and `[`/`]` cycled images. The code binds ↑/↓ to LUTs and
  both `←`/`→` and `[`/`]` to images.
- Shipped but undocumented: the intensity slider, the Info inspector (⌘I), the source-folder browser
  (⌘⌥I) and its refresh (⌘R), and Export All (⌘⇧E).
- The project-structure tree omitted four files: `Models/Histogram.swift`, `Models/ImageMetadata.swift`,
  `Views/InfoInspectorView.swift`, `Views/SourceBrowserView.swift`.
- "Responsive by design… LUT application is cancellable" described an intention, not the code (B2).

**Second wave, found by the second opposition pass · [fixed].** The README was last edited at
`773121a` (Phase 2 Step 5) and went **71 commits** without one — Steps 6 through 10b, two inspectors
and a deleted type all landed behind it. It is the file nobody works in, which is exactly why it rots
hardest, and pass 1 never opened it.

- The project-structure tree listed `Models/ImageProcessor.swift`, deleted in Step 7 — 9 grep hits at
  HEAD, all comments describing it in the past tense. It also showed **24 source files against 43 on
  disk** and 10 test files against 35, while terminating every directory with `└──`, which asserts
  closure. Regenerated; the test half now says explicitly that it is a selection.
- `:231` named `ImageProcessor.orientedLoadOptions` in the present tense (it is `ImageDecoder`'s).
- The Features section and the `⌘I` shortcut row documented a one-tab histogram/EXIF inspector. It has
  had three tabs since Step 10b. §4b fixed the *in-app* twin of this and left the README, because the
  README was not on anyone's list.
- "188 tests" (322 at HEAD), and the skip breakdown was absent.
- **The build section promised what no build path delivers**: "full app behavior, icon, and App
  Sandbox" from Xcode. `Package.swift:26` excludes both `Assets.xcassets` and `LUTzy.entitlements`
  from the target, `AppIcon.appiconset` holds no images, and there is no `Info.plist` or bundle
  identifier anywhere — so both paths build a bare SwiftPM executable. The knock-on: the Features
  claim that folder access "survives restarts through App Sandbox security-scoped bookmarks" is
  unreachable from any documented build. `CLAUDE.md:9` carried the identical line and survived a
  commit that edited that same file. Both now say what is actually true.

---

## 4b. In-app copy drift · [fixed]

Found by the opposition pass, which harvested claims from documentation and doc comments but not from
the strings the app actually shows. Every item below is verified against HEAD. **None is a correctness
bug** — they are all cases where shipped copy describes an older, smaller app — but they are the copy a
user reads, which makes them worse than a stale spec line, not better.

All four are corrected. Each was a wording decision rather than a mechanical fix, so the reasoning is
recorded beside the string in the source.

- **Export All's tooltip** read "Apply the current **LUT** to all imported images", while
  `ExportCoordinator.performBatchExport` takes an `EditDocument` and applies the whole look —
  `rawDevelop` and `adjustments` included — to every image in the folder. The shipped-UI twin of the
  README drift fixed above, and the more consequential one: the document's `rawDevelop` was seeded from
  *one* RAW's as-shot values, and the tooltip gave no hint those travel to every other file. Now names
  all three.
- **The inspector button and the empty state** named only the Info tab ("Show histogram & EXIF",
  "Open an image to see its histogram and EXIF data") though the inspector has been a three-tab
  Info/Develop/Adjust picker since Step 10b. The empty state matters more than it looks: it stands in
  for the *whole* inspector when nothing is open, not for the Info tab. Both name all three now.
- **The Sharpening badge's hint** read "applied separately, not in LUT", promising a second stage that
  does not exist: `sharpeningRatio` is measured, carried on the report and displayed, with no consumer
  anywhere in the render path. Now "measured, not applied".
- **`geometryMismatch`'s message** said the two files "must be the same frame at the same aspect
  ratio", but the guard compares aspect only, within `aspectTolerance`. Differing pixel dimensions are
  accepted by design — reconciling them is what the Lanczos step is for — so the message overstated the
  requirement it was explaining, and named "shapes" for what is really an aspect check. Now says so.

**Also fixed, same class: the ship gate itself.** Every step plan ends with a gate of the shape
`git diff --stat main -- <load-bearing files>`, "Expected: **no output**". Step 10b's would have failed
on the merge that shipped it — re-run against its own merge base, `AdjustmentNode.swift` and
`RenderPipeline.swift` both moved. **The design intent held perfectly**: every changed line is a doc
comment, and the changes are the §8.7 closures. The defect is in the gate, which cannot tell a comment
from a statement, and a gate nobody can pass gets ignored — which is worse than no gate.

`scripts/code-diff-gate.sh <base-ref> <file>...` asks the question the plans meant to ask. Comment-only
edits pass; one moved statement fails, and prints the diff that failed it. Verified against the case
that motivated it — on Step 10b's merge, `git diff --stat` reports two changed files and this reports
`PASS — no executable line moved` — and against a real code change, where it names the line.

It strips whole-line `//` and `///` comments only: not trailing comments, not `/* */`, and it is not a
parser, so a `//` inside a string literal stays. Deliberate, and the script says so. Over-stripping
would let a real change hide, which is the failure it exists to prevent; under-stripping costs a false
alarm you can read.

---

## 4c. What the correction passes got wrong · [fixed]

Two opposition passes have run over this repo. The second one's most useful output was not the drift
it found in old code — it was the drift the **first pass introduced while correcting other drift**.
Recorded here in full, because a correction process that cannot audit itself is just a slower way of
being wrong.

- **It wrote a false invariant.** "At most one probe is ever in flight, because there is only one
  handle to hold it" (`AppViewModel`, and copied into B15 above). One handle bounds how many tasks you
  can still *cancel*, not how many are unfinished: cancelling cannot resume a task already suspended
  inside `rawCapabilities(for:)`, and the guard sits after that `await`. `LoadCancellationTests`
  reaches two live probes by design. The safety argument was sound; the mechanism offered to justify
  it was not.
- **Its own guard had the hole it was written to close.** `DeriveBaselineImmunityTests` claimed *any*
  new parameter on `derive` would fail it. Its parser read one label per line, so
  `isCancelled: (() -> Bool)? = nil, exposureBias: Double = 0` parsed to the same five labels and
  passed with a sixth parameter present — in the test that exists specifically because the previous
  coverage claim was vacuous.
- **A test that could not fail.** `FakeRenderEngine` held one continuation slot, so a second parked
  probe overwrote the first and the first was never resumed — the runtime prints
  `SWIFT TASK CONTINUATION MISUSE` and XCTest does not fail on it. It also read `stubbedCapabilities`
  *after* the suspension, so two probes could not be told apart. Measured: deleting
  `refreshCapabilities()`'s cancellation left `testASuccessfulOpenStillReplacesThePreviousProbesAnswer`
  green, which is the exact thing its failure message claims to pin.
- **It armed a gate it never ran.** PR #28 added `SKIPPED` to both harnesses' exit gates, arguing that
  "an exit code that is always 1 says nothing" — and did not run `mutate-step10a.sh`, which had been
  exiting 1 on ten dead anchors since Step 10b. It verified the sibling harness and assumed a shared
  classifier meant a shared fate. See B17.
- **Its diagnosis was inverted.** The `xctest` explanation in `mutate-step9.sh` and the PR #27 body
  said the negation "could never fire, because xctest prints `and 0 failures`, not `with 0 failures`".
  A non-skipping suite prints exactly `with 0 failures`, so the negation fired constantly. The fix was
  right; the reason recorded beside it taught the opposite of the truth.
- **It fixed the doc and left the code twin, twice.** The header comment and README learned that derive
  scales *both* images while the user-facing progress string kept saying "Scaling RAW to JPG
  resolution". `PHASE2_SPEC` learned the mutation tally had been re-measured while the harness four
  lines above the rewritten paragraph still said it never had.
- **It replaced one hardcoded measurement with another.** §3's "4,180 lines" became "534 lines" — the
  same failure mode with a shorter fuse. It was already 541 by the next commit.
- **It updated a number and left its sibling.** `PHASE2_SPEC` §6 read "22 skip without a DNG… the
  other 17 are the RAW-gated ones". 3 + 17 = 20. The 17 was right when the total was 20, and the
  sentence containing it was itself correcting an earlier miscount.
- **It never opened the README.** Findings across §4's second wave are one omission: 71 commits of
  drift in the file nobody works in, invisible to a process that greps for claims in the files people
  do work in.

The through-line: **every one of these is a sentence that was true when written.** None was careless
at the time. That is what makes prose an unreliable place to keep a fact, and why the fixes that
matter in both passes were the mechanical ones — `DocumentedTestNamesTests`, `code-diff-gate.sh`,
`--check` — rather than the corrected sentences.

---

## 5. Suggested order for the follow-up work

1. ~~**`LUTzyKit` split + test target.**~~ **Done** — see §2.
2. ~~**Split `AppViewModel` and the rest of `ContentView`.**~~ **Done** — see §3.
3. ~~**Distil `PHASE2_SPEC.md`**~~ **Done** — 292 lines, §6 of it is the ordered migration.

**Phase 2 itself is now the only work left.** _As written, Steps 0–2 were complete and Step 3 was
next. At HEAD that paragraph is four steps stale — **Steps 0–10b have shipped**, and the value-state
types it describes as "defined but not yet referenced by anything" are the spine the whole render path
runs on. See `PHASE2_SPEC.md` §6 for the current row-by-row state; **Step 11 (`EditDocumentStore`,
undo, per-image edits) is what is actually next.** Left in place rather than rewritten, because §5 is a
record of what the review recommended, not a status board — the correction belongs beside it._

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
