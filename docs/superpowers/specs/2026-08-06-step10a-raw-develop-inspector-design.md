# Phase 2 Step 10a — the RAW develop inspector

**Date:** 2026-08-06
**Ship gate (`PHASE2_SPEC.md` §6):** RAW develop + adjustments inspector, gated per-image on the real
`is*Supported` flags; the inspector drives a live re-render.

**Step 10 is split.** This spec covers **10a**: the capability probe and the RAW develop panel — the
half that carries the new architecture and the ship gate's wording. **10b** adds the adjustments
stack (fixed slots, one node of each, in canonical pipeline order) and is specified separately once
10a is reviewed. Splitting keeps the probe's design reviewable before a second panel is built on it.

---

## 1. The problem the step actually poses

The gate says "gated per-image on the real `is*Supported` flags". Those flags live on `CIRAWFilter`,
which is **not `Sendable`** and, per §4.5, is born and dies inside `actor RenderEngine`. The only
reference to them today is inside `RAWDevelopSettings.apply(to:)`, which already runs in there.

A SwiftUI inspector is `@MainActor`. It cannot read a `CIRAWFilter`. So the flags have to be probed
inside the actor and cross the boundary as a value. That is the one genuinely new piece of
architecture in this step; everything else is UI over the `updateDocument` seam Step 5 left behind
for exactly this purpose.

### Measured first

Constructing a `CIRAWFilter` and reading every flag, without ever touching `outputImage`, on the
30 MB Leica DNG in `realworldtest/`:

| | ms |
|---|---|
| probe, cold | 169.6 |
| probe, warm (×4) | 25.8, 25.2, 25.4, 25.8 |
| a full develop for comparison (filter → `outputImage` → rasterize) | 183.2 |

So the probe is real but small — about 14% of a decode — and it is emphatically **once per image**,
never per render and never per slider tick.

### Two findings that changed the design

**1. `CODE_REVIEW.md` §5 is wrong about the gates being untestable.** It says: "The `is*Supported`
gates in `apply(to:)` are not covered at all: that needs a RAW whose decoder *lacks* an adjustment,
and the Leica file supports every one of them." Measured:

```
sharpness ✓  contrast ✓  detail ✓  moiré ✓
localToneMap ✗  lumaNR ✓  colorNR ✓  lensCorrection ✓
```

`isLocalToneMapSupported` is **false**, so the claim's stated reason is wrong and there is a gated
branch to aim at.

**As built, with the overclaim removed.** Aiming at it on pixels is not enough. Writing
`localToneMapAmount` against this decoder does render byte-identically to leaving it unset — but so
does the same test with our gate *deleted from `apply(to:)`*, at a worst pixel delta of exactly 0:
`CIRAWFilter` silently discards writes to properties its decoder does not implement, so the
framework's own gate absorbs the write whether ours ran or not. The pixel test therefore pins the
end-to-end behaviour and nothing about our code, and is named
`testAValueWrittenToAnUnsupportedAdjustmentChangesNothing` to say so. Our gate is covered instead by
`RAWDevelopSettingsTests.testEveryGatedAdjustmentIsAppliedOnlyBehindItsOwnSupportedFlag`, which reads
the source text of `apply(to:)` and checks each of the nine properties is written only behind its own
flag. `CODE_REVIEW.md` §5 is corrected to say exactly that, and no more.

_(Said "eight" as written; corrected by the opposition pass. Eight is the gated **seed** count —
highlight recovery has no per-image seed — and nine is the gated **write** count, which is what this
sentence is about.)_

**2. The probe cannot return only flags.** As-shot white balance on this file is
`temp = 5842.2, tint = 14.04` — not a round default. Every `RAWDevelopSettings` property is
`Optional` and `nil` means "leave `CIRAWFilter` at its decoder default", and several of those
defaults **vary per image** (`baselineExposure`, `shadowBias`, and the as-shot WB). A slider bound to
`nil` therefore has nothing to display. The probe must carry the per-image seed values or the white
balance control cannot be drawn at all.

---

## 2. `RAWCapabilities`

A new `Sendable` value in `Models/`:

```swift
struct RAWCapabilities: Sendable, Equatable {
    // Gates — one per adjustment CIRAWFilter can refuse.
    var isSharpnessSupported: Bool
    var isContrastSupported: Bool
    var isDetailSupported: Bool
    var isMoireReductionSupported: Bool
    var isLocalToneMapSupported: Bool
    var isLuminanceNoiseReductionSupported: Bool
    var isColorNoiseReductionSupported: Bool
    var isLensCorrectionSupported: Bool
    /// False below macOS 26, where the property is not in the imported interface at all.
    var isHighlightRecoverySupported: Bool

    // Per-image seeds. Without these a control bound to a nil setting has nothing to show.
    var asShotTemperature: Double
    var asShotTint: Double
    var baselineExposure: Double
    var shadowBias: Double
}
```

**As built: twelve seeds, not four.** The four above are the ones this design anticipated. Eight more
shipped with the panel, because `RAWDevelopSettings`' own type doc is explicit that the
noise-reduction and sharpening defaults **vary per image** too, and the panel was otherwise binding
those sliders to guessed constants — a hardcoded `0`, and `true` for lens correction. The added
fields are `sharpnessAmount`, `contrastAmount`, `detailAmount`, `moireReductionAmount`,
`localToneMapAmount`, `luminanceNoiseReductionAmount`, `colorNoiseReductionAmount` and
`lensCorrectionEnabled`. Each is read in `RenderEngine.rawCapabilities(for:)` **only behind its own
`is*Supported` flag** — asking a decoder for a sharpening amount it does not offer answers nothing —
which is a property with no runtime trace, so
`RAWCapabilitiesTests.testEveryGatedSeedIsReadBehindItsOwnSupportedFlag` reads source text to keep it.

The finding in one number: the Leica's real `sharpnessAmount` is **0.7349015474319458**. That slider
was opening at 0 — three quarters of the way from where the picture actually was — so the first touch
of it jumped the image hard. `colorNoiseReductionAmount` at 0.5 is the same defect, smaller, and
`lensCorrectionEnabled` is `true` on this file where the old getter said `false`.

**And one seed did not fit the slider it was meant to fill.** `shadowBias` seeds at **5.0**, against a
range this plan had invented as `-1...1` — that control opened pinned at its maximum on this camera
and could only be dragged down. It is now `-10...10`: round and symmetric like the other two
undocumented ranges, with 5.0 well clear of either edge. Recorded as **observational, from a single
camera**, not as a documented `CIRAWFilter` bound — `DevelopControl.range`'s doc comment says so, and
`RAWCapabilitiesTests.testEveryPerImageSeedLandsStrictlyInsideItsSliderRange` re-checks every seed
against its range whenever a real DNG is present, which is the check that would have caught it first.

Probed through a new protocol method, so a test can supply capabilities without a RAW:

```swift
/// nil for a non-RAW source — there is no CIRAWFilter to ask.
func rawCapabilities(for source: ImageSource) async -> RAWCapabilities?
```

`RenderEngine` implements it by building a throwaway `CIRAWFilter` and reading the flags. It
deliberately never touches `outputImage`: that is the difference between 25 ms and 183 ms, and the
developed-source memo must not be disturbed by a capability question.

`AppViewModel` gains `@Published private(set) var rawCapabilities: RAWCapabilities?`, refreshed once
per image open, in a task that runs alongside the preview render rather than in front of it. It is
cleared when a non-RAW image opens.

**Not cached across images.** One entry would be a memo keyed on `ImageSource`, and the win is 25 ms
on returning to an image the user already had open — against the cost of another cache whose
invalidation nobody will remember. Revisit only if filmstrip stepping measures badly.

---

## 3. `nil` versus a written value

This is the subtle part of the panel, and it is where a careless implementation breaks an invariant
the whole migration rests on.

`RAWDevelopSettings.neutral` is byte-identical to `ImageDecoder.developRAWNeutral` **because it sets
nothing at all**. If merely opening the Develop panel wrote concrete values into every field, the
document would stop being neutral, `isNeutral` would go false, and the derive baseline (§5, "derive
baseline immunity") would be reasoning about a document that is no longer the neutral one.

So:

- A control **displays** the effective value: the stored setting when non-`nil`, otherwise the seed
  from `RAWCapabilities` (or the documented fixed default, for knobs that have one — `exposure` 0,
  `boostAmount` 1, `boostShadowAmount` 1, `extendedDynamicRangeAmount` 0, `gamutMappingEnabled` true).
- A control **writes** a concrete value only when the user actually moves it.
- A per-control reset writes `nil` back, and a panel-level "Reset develop" sets `.neutral`.
- Opening the panel writes nothing.

Pinned by a test: writing the probed as-shot temperature and tint renders identically (tolerance 1)
to leaving both `nil`. If that ever fails, the seeds the probe reports are not the values the decoder
actually used, and every control in the panel is lying about its starting point.

---

## 4. Debouncing

`updateDocument` re-renders synchronously, and when `rawDevelop` changed it *also* calls
`scheduleOriginalPreview()`. A develop slider drag would therefore issue **two full re-renders per
tick**, one of them for the side-by-side baseline nobody is looking at mid-drag.

§6 is explicit: debounce continuous edits only. Develop edits get the same 60 ms debounce
`setLUTIntensity` already uses, via a new `updateDocument(debounced:_:)` — discrete controls
(toggles, resets) stay immediate, so a checkbox still feels instant, and the existing immediate
`updateDocument` keeps working unchanged for tests and for Step 11.

Open and filmstrip navigation stay immediate, per the same section.

---

## 5. Placement and gating

A segmented **Info / Develop** control at the top of the existing `⌘I` inspector. One inspector
column, two modes: it reuses the `.inspector()` plumbing already in `ContentView`, and it keeps the
histogram one click from the sliders, which matters because watching the histogram while dragging
exposure is the actual workflow.

Gating has two levels, and they are different things:

- **Source kind.** `RenderPipeline.developedSource` switches on `source.kind` and ignores
  `rawDevelop` entirely for a standard image. Offering the controls would be offering a lie — the
  model would accept the value and the renderer would drop it.

  **Changed deliberately during implementation.** This section originally said the Develop segment
  would be *disabled* on a non-RAW. What shipped is the opposite: the segment stays live, and
  selecting it shows a full explanation panel — an aperture glyph, "No develop stage", and "Develop
  controls come from the RAW decoder. This image is already rendered." (`DevelopInspectorView.notRAW`).
  A disabled segment says *no* without saying *why*, which is the same complaint that got unsupported
  adjustments hidden rather than greyed out one bullet below; a panel that answers the question is
  strictly better, and costs a dozen lines. The one case where nothing is offered is **no image at
  all** — `InfoInspectorView` hides the switcher entirely then, because both tabs describe a picture
  and there isn't one.
- **Per-adjustment support.** Within a RAW, an unsupported control is **hidden**, not disabled — a
  greyed-out slider invites the user to wonder what they did wrong, where absence reads correctly as
  "this camera's decoder does not do that". This mirrors exactly what `apply(to:)` already enforces.
  On the Leica it means Local Tone Map does not appear.

**The control list is a value, not a view.** Which controls a panel offers comes from a pure
`RAWCapabilities.availableControls: [DevelopControl]` — an ordered array of a small enum — and the
view is a `ForEach` over it. That is what makes the gating testable at all: this repo has no SwiftUI
view tests and cannot easily get them, so a gate expressed only as `if capabilities.isXSupported` in
a `ViewBuilder` would be unverifiable. Expressed as a value it is one assertion.

`InfoInspectorView` is already 193 lines and would roughly double. The develop panel goes in a new
`DevelopInspectorView.swift`, with the segmented switch owned by a small container — consistent with
the Step-7 precedent of splitting `ContentView.swift` when it accumulated unrelated types.

---

## 6. Testing

The ship gate is "the inspector drives live re-render", which is a claim about wiring, so most of
this rides on `FakeRenderEngine` recording requests. Two things need real pixels.

| test | pins |
|---|---|
| `testDevelopEditRendersTheChangedDocument` | the gate: a develop change reaches the engine as a render request carrying it |
| `testADragIssuesFarFewerRendersThanTicks` | the debounce; N ticks → a handful of renders, not N |
| `testDevelopEditsAreInertForAStandardImage` | a standard image's render is unchanged by `rawDevelop` |
| `testCapabilitiesAreProbedOncePerOpen` | not per render, not per tick — the 25 ms stays off the drag |
| `testUnsupportedAdjustmentsAreNotOffered` | **the gate `CODE_REVIEW.md` §5 called untestable** — `availableControls` omits Local Tone Map for the Leica, and `apply(to:)` drops a written value for it |
| `testWritingTheAsShotValuesMatchesLeavingThemNil` | real pixels, tolerance 1 — the seeds are the decoder's actual values |
| `testOpeningThePanelWritesNothing` | `document.rawDevelop.isNeutral` survives presenting the inspector |

The last three are RAW-gated and **skip on CI**, which has no DNG. That will be said in the skip
messages and the PR body rather than left to look like coverage.

**As built, the names drifted and one row split.** `testOpeningThePanelWritesNothing` is
`testReadingEveryControlWritesNothing` (the panel is a view, and this repo has no view tests, so the
assertion drives every binding's getter — the thing that could write). `testUnsupportedAdjustmentsAreNotOffered`
became three: `availableControls` gating against a synthetic capability value, the real decoder's
flags through the probe, and — because the pixel half of that row turned out to prove nothing about
our own gate (§1) — a source-text test over `apply(to:)`. The seed table grew its own tests with the
eight extra seeds (§2), including a range check that catches a seed opening a slider pinned.

**`testDevelopEditsAreInertForAStandardImage` was listed here but not built**, and nothing else in
the suite asserted that `RenderPipeline.developedSource` ignores `rawDevelop` on the `.standard`
arm — a row in this table standing in for coverage that did not exist. It has since been written,
in `RenderPipelineTests`, and it needs no RAW: build a document with every develop knob set far from
its default, render the PNG fixture with it and without it, and assert the pixels match. It runs
everywhere, CI included.

**A row the table did not have, added after the fact.** The panel has **three** states, not two —
not a RAW, a RAW whose 25–170 ms capability probe has not landed, and a probed RAW — and shipping it
with two meant a RAW opened on the Develop tab read "No develop stage … this image is already
rendered" for the length of the probe. The distinction lives in
`AppViewModel.DevelopPanelState` for the usual reason (no SwiftUI view tests here), and is pinned by
`testThePanelStateMappingCoversAllThreeStates` (the mapping, on any machine) plus
`testARAWStaysOnProbingUntilTheProbeAnswers` (that a real RAW genuinely occupies the middle state —
RAW-gated, so it skips on CI).

Every regression test is mutation-checked with a harness reporting *caught*, *survived*, *did not
compile*, *no tests ran* and *skipped* separately — `scripts/mutate-step9.sh` is the template, and
its lesson is worth repeating here: classify on structure (`file:line:col: error:` versus
`error: -[Suite test]`), never by grepping message text.

---

## 7. Files

| file | change |
|---|---|
| `Models/RAWCapabilities.swift` | **new** |
| `Models/RenderEngine.swift` | `rawCapabilities(for:)` on the protocol and the actor |
| `ViewModels/AppViewModel.swift` | published capabilities, probe on open, debounced develop edits |
| `Views/DevelopInspectorView.swift` | **new** — the panel |
| `Views/InfoInspectorView.swift` | segmented Info/Develop container |
| `Tests/…` | §6, plus `FakeRenderEngine` conformance |
| `docs/CODE_REVIEW.md` | correct the §5 claim that the gates are untestable |
| `docs/PHASE2_SPEC.md` | §6 row split into 10a/10b; record the measured probe cost |

## 8. Out of scope

The adjustments stack (**10b**), per-image undo and `EditDocumentStore` (Step 11), edit persistence
across launches (§8.8), and the `CITemperatureAndTint` direction question (§8.7). That last one is
deferred *by decision*: RAW white balance is the temperature control for a RAW, and the
`temperatureTint` node is reserved for non-RAW images in 10b, so no image ever shows two Kelvin
sliders and §8.7 does not block this step.

`rawDevelop` not resetting on new-image open is also deferred *by decision*, not overlooked. §8.4's
Step 5 "keep `document` across opens" call predates develop being reachable at all; 10a is what makes
its cost visible — a `neutralTemperature` set on one RAW now overrides the next RAW's own as-shot seed
instead of yielding to it, and `originalForComparison` inherits the same staleness. Fixing it belongs
with Step 11's `EditDocumentStore`, which is where "which document belongs to which image" becomes a
per-image question instead of a single global one; see §8.4 for the full argument.
