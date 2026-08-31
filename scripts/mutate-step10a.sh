#!/bin/bash
# Mutation check for Phase 2 Step 10a — the RAW develop inspector.
#
# Break the code one edit at a time and confirm the *named* test fails. A mutation that fails to
# build, runs no tests, or is skipped is NOT a pass — those are reported separately, because a
# harness that folds them into "caught" silently turns a compile error into evidence of coverage.
#
# The classifier below is identical to `scripts/mutate-step9.sh`'s; see the comment inside it for why
# it must classify on structure and never on message text, and why a failure is looked for before a
# skip. That was not true for a while: this file fixed the ordering bug and step9 kept the broken
# classifier, so the two diverged in the direction that mattered. **They must be changed together.**
#
# **Several of these run against the untracked Leica DNG in `realworldtest/`.** Where a mutation is
# only observable through a real decoder it is marked below. On CI those tests `XCTSkip`, and the
# harness reports SKIPPED — which proves nothing, and is why it is a separate outcome.
#
# Usage: scripts/mutate-step10a.sh
set -uo pipefail
cd "$(dirname "$0")/.."

PASS=0; SURVIVED=0; NOBUILD=0; NORUN=0; SKIPPED=0; CONTROL=0; CONTROL_CAUGHT=0
declare -a SURVIVOR_NAMES=() NOBUILD_NAMES=() NORUN_NAMES=() CONTROL_CAUGHT_NAMES=()

# mutate <label> <file> <perl-expr> <test-filter>
mutate() {
  local label="$1" file="$2" expr="$3" filter="$4"
  cp "$file" "$file.bak"
  perl -0pi -e "$expr" "$file"

  if cmp -s "$file" "$file.bak"; then
    echo "NO-OP     $label — the pattern did not match; the mutation never applied"
    NORUN=$((NORUN+1)); NORUN_NAMES+=("$label (pattern did not match)")
    mv "$file.bak" "$file"; return
  fi

  local out
  out="$(swift test --filter "$filter" 2>&1)"
  mv "$file.bak" "$file"

  # Classify on structure, never on message text. A compiler diagnostic is
  # `file.swift:LINE:COL: error: …`; an XCTest failure is `file.swift:LINE: error: -[Suite test] …`.
  # An earlier version of this grepped for words like "cannot" and "expected" anywhere after
  # `error:`, and duly reported nine caught mutations as NO-BUILD because the *assertion messages*
  # contained those words. Scoring a caught mutation as "proves nothing" is the safe direction to be
  # wrong in, but it is still wrong.
  local ran
  ran="$(grep -oE "Executed [0-9]+ tests?" <<<"$out" | head -1 | grep -oE "[0-9]+")"

  if [[ -z "${ran:-}" ]]; then
    if grep -qE "^[^ ]+\.swift:[0-9]+:[0-9]+: error:" <<<"$out" || grep -q "error: fatalError" <<<"$out"; then
      echo "NO-BUILD  $label — did not compile, so this mutation proves nothing"
      NOBUILD=$((NOBUILD+1)); NOBUILD_NAMES+=("$label")
    else
      echo "NO-TESTS  $label — the suite never ran under filter '$filter'"
      NORUN=$((NORUN+1)); NORUN_NAMES+=("$label (suite did not run)")
    fi
    return
  fi

  if [[ "$ran" == "0" ]]; then
    echo "NO-TESTS  $label — no tests matched filter '$filter'"
    NORUN=$((NORUN+1)); NORUN_NAMES+=("$label (filter matched nothing)")
    return
  fi

  # **A failure is looked for FIRST, and SKIPPED only after.** These two were the other way round,
  # and the old skip test — `with N tests skipped and 0 failures`, negated against a loose
  # `with [0-9]* failures` — matched a run that both skipped *and* failed on a machine without the
  # DNG: several filters here name suites that mix RAW-gated tests with ordinary ones, so a genuine
  # survivor in such a suite was reported SKIPPED, and SKIPPED is (correctly) excluded from the
  # `exit 1` at the bottom. The harness would have exited 0 on an uncaught mutation. Detecting the
  # failure first cannot make that mistake: a run that skipped some tests and failed others is
  # caught, which is what it is.
  #
  # Note the failure pattern has to tolerate the skip clause sitting between "with" and the failure
  # count — xctest prints `with 1 test skipped and 2 failures` — and the previous `with [1-9]`
  # shorthand cannot be reused here, because it also matches `with 1 test skipped and 0 failures`.
  # That is precisely why the skip branch had to run first before, and why it no longer has to.
  #
  # **The tally recorded in the commit message / PR body was produced on a machine where the DNG in
  # `realworldtest/` was present and every filter above ran with zero skips.** A run reporting any
  # SKIPPED is a weaker run than that one, whatever its caught count says.
  # A label beginning with CONTROL marks a **deliberate equivalent mutant** — a change that provably
  # cannot alter behaviour, carried so the harness proves it can still tell a survivor from a kill.
  # It is expected to survive, so it must not count toward SURVIVED.
  #
  # It did, and the arithmetic was fatal: `mutate-step9.sh` carries one control and gated on
  # `SURVIVED -eq 0`, so **it could never exit 0 on any run**, however healthy. An exit code that is
  # always 1 says nothing, which is the same disease as a SKIPPED that was always excluded — a
  # signal nobody can act on. Counted separately here so the exit code means something again.
  #
  # A control that gets CAUGHT is its own finding, and fails the run: it means a test now asserts
  # something the mutation proves is unobservable — an implementation detail, not behaviour. The fix
  # then is to loosen the test, never to delete the control.
  local is_control=0
  [[ "$label" == CONTROL* ]] && is_control=1

  if grep -qE "with ([0-9]+ tests? skipped and )?[1-9][0-9]* failures?" <<<"$out"; then
    if [[ $is_control -eq 1 ]]; then
      echo "CTRL-KILL $label — a control was caught; some test is asserting an implementation detail"
      CONTROL_CAUGHT=$((CONTROL_CAUGHT+1)); CONTROL_CAUGHT_NAMES+=("$label -> $filter")
    else
      echo "caught    $label"
      PASS=$((PASS+1))
    fi
    return
  fi

  if grep -qE "with [0-9]+ tests? skipped and 0 failures" <<<"$out"; then
    echo "SKIPPED   $label — the test skipped rather than running"
    SKIPPED=$((SKIPPED+1))
    return
  fi

  if [[ $is_control -eq 1 ]]; then
    echo "control   $label — survived, as it must"
    CONTROL=$((CONTROL+1))
    return
  fi

  echo "SURVIVED  $label — '$filter' still passed with the code broken"
  SURVIVED=$((SURVIVED+1)); SURVIVOR_NAMES+=("$label -> $filter")
}

VM=Sources/LUTzyKit/ViewModels/AppViewModel.swift
RC=Sources/LUTzyKit/Models/RAWCapabilities.swift
RE=Sources/LUTzyKit/Models/RenderEngine.swift
RD=Sources/LUTzyKit/Models/RAWDevelopSettings.swift

echo "=== gating: which controls a file offers ==="
mutate "RAWCapabilities: offer every control regardless of support" "$RC" \
  's/DevelopControl\.allCases\.filter\(supports\)/DevelopControl.allCases/' \
  "RAWCapabilitiesTests"
mutate "RAWCapabilities: a gated control reports supported" "$RC" \
  's/case \.localToneMap: return isLocalToneMapSupported/case .localToneMap: return true/' \
  "RAWCapabilitiesTests"
mutate "RAWCapabilities: two gated arms swapped" "$RC" \
  's/case \.contrast: return isContrastSupported\n        case \.detail: return isDetailSupported/case .contrast: return isDetailSupported\n        case .detail: return isContrastSupported/' \
  "RAWCapabilitiesTests"
mutate "RAWCapabilities: the ungated arm reports unsupported" "$RC" \
  's/            return true\n        case \.sharpness: return isSharpnessSupported/            return false\n        case .sharpness: return isSharpnessSupported/' \
  "RAWCapabilitiesTests"

echo "=== DevelopControl: isToggle and range, which moved off AppViewModel in Task 5 ==="
# The brief's draft aimed these two at `AppViewModel`. Both now live on `DevelopControl` in
# `RAWCapabilities.swift`, so the old patterns would have reported NO-OP — which proves nothing.
mutate "DevelopControl: the Bool-backed controls stop being toggles" "$RC" \
  's/case \.lensCorrection, \.gamutMapping, \.highlightRecovery:\n            return true/case .lensCorrection, .gamutMapping, .highlightRecovery:\n            return false/' \
  "RAWCapabilitiesTests"
mutate "DevelopControl: boost and boostShadow share one range" "$RC" \
  's/case \.boost: return 0\.\.\.1\n        case \.boostShadow: return 0\.\.\.2/case .boost, .boostShadow: return 0...2/' \
  "RAWCapabilitiesTests"
# shadowBias seeds at 5.0 on the Leica; the plan had invented -1...1, which does not contain it.
mutate "DevelopControl: shadowBias back to the invented -1...1 range" "$RC" \
  's/case \.shadowBias: return -10\.\.\.10/case .shadowBias: return -1...1/' \
  "RAWCapabilitiesTests"

echo "=== the probe ==="
mutate "RenderEngine: report capabilities for a standard image too" "$RE" \
  's/        guard case \.raw = source\.kind else \{ return nil \}\n//' \
  "RAWCapabilitiesTests|DevelopInspectorTests"
mutate "RenderEngine: return a blank as-shot temperature" "$RE" \
  's/            asShotTemperature: Double\(filter\.neutralTemperature\),/            asShotTemperature: 0,/' \
  "RAWCapabilitiesTests"
# The probe's cost claim — ~25 ms versus ~183 ms for a develop — rests on never evaluating the
# graph, and on not disturbing the engine's developed-source memo. Invisible to a value assertion.
mutate "RenderEngine: the probe evaluates outputImage" "$RE" \
  's/        guard let filter = RenderPipeline\.rawFilter\(for: source\.backing\) else \{ return nil \}\n/        guard let filter = RenderPipeline.rawFilter(for: source.backing) else { return nil }\n        _ = filter.outputImage\n/' \
  "RAWCapabilitiesTests"

echo "=== the panel's three states ==="
# `rawCapabilities` is nil both for "no develop stage" and for "the probe has not landed", and the
# panel used to collapse the two — so a RAW opened on the Develop tab was told, in words, that it had
# no develop stage for the 25-170 ms of the probe. The first mutation is that regression exactly.
mutate "AppViewModel: the in-flight probe reports 'no develop stage' again" "$VM" \
  's/                self = sourceIsRAW \? \.probing : \.noDevelopStage/                self = .noDevelopStage/' \
  "DevelopInspectorTests"
mutate "AppViewModel: capabilities no longer win over the source kind" "$VM" \
  's/            if let capabilities \{\n                self = \.ready\(capabilities\)\n            \} else \{/            if let capabilities, sourceIsRAW {\n                self = .ready(capabilities)\n            } else {/' \
  "DevelopInspectorTests"
# RAW-gated: `ImageSource.kind` for a URL comes from the file extension, and `AppViewModel` only
# records a source for a file that actually decoded, so only a real DNG reaches the `.raw` arm.
mutate "AppViewModel: no image is ever a RAW" "$VM" \
  's/    var sourceIsRAW: Bool \{ imageSource\?\.kind == \.raw \}/    var sourceIsRAW: Bool { false }/' \
  "DevelopInspectorTests"

echo "=== the twelve seeds: read behind the right flag, and read at all ==="
# Task 1 shipped four per-image seeds; Tasks 3-6 grew that to twelve, because
# `RAWDevelopSettings`' own type doc says the noise-reduction and sharpening defaults vary per
# image and the panel was showing guessed constants. The Leica's real sharpnessAmount is 0.7349 —
# that slider was opening at 0.
mutate "RenderEngine: a seed read behind the wrong flag (sharpness gated on contrast)" "$RE" \
  's/sharpnessAmount: filter\.isSharpnessSupported \? Double\(filter\.sharpnessAmount\) : 0/sharpnessAmount: filter.isContrastSupported ? Double(filter.sharpnessAmount) : 0/' \
  "RAWCapabilitiesTests"
mutate "RenderEngine: a gated seed not read at all (localToneMap hardcoded 0)" "$RE" \
  's/            localToneMapAmount:\n                filter\.isLocalToneMapSupported \? Double\(filter\.localToneMapAmount\) : 0,/            localToneMapAmount: 0,/' \
  "RAWCapabilitiesTests"
mutate "AppViewModel: a control displays another control's seed" "$VM" \
  's/        case \.sharpness: return develop\.sharpnessAmount \?\? seed\?\.sharpnessAmount \?\? 0/        case .sharpness: return develop.sharpnessAmount ?? seed?.contrastAmount ?? 0/' \
  "DevelopInspectorTests"
mutate "AppViewModel: a control ignores its seed and opens at zero" "$VM" \
  's/            return develop\.colorNoiseReductionAmount \?\? seed\?\.colorNoiseReductionAmount \?\? 0/            return develop.colorNoiseReductionAmount ?? 0/' \
  "DevelopInspectorTests"
mutate "AppViewModel: the lens-correction toggle ignores its Bool seed" "$VM" \
  's/return \(develop\.lensCorrectionEnabled \?\? seed\?\.lensCorrectionEnabled \?\? false\) \? 1 : 0/return (develop.lensCorrectionEnabled ?? false) ? 1 : 0/' \
  "DevelopInspectorTests"
mutate "AppViewModel: the tint binding ignores its seed" "$VM" \
  's/self\.document\.rawDevelop\.neutralTint \?\? self\.rawCapabilities\?\.asShotTint \?\? 0/self.document.rawDevelop.neutralTint ?? 0/' \
  "DevelopInspectorTests"

echo "=== probing once per open ==="
mutate "AppViewModel: never probe on open" "$VM" \
  's/                self\.refreshCapabilities\(\)\n//' \
  "DevelopInspectorTests"
mutate "AppViewModel: probe on every render" "$VM" \
  's/^        let \(requested, lut\) = displayRequest$/        refreshCapabilities()\n        let (requested, lut) = displayRequest/m' \
  "DevelopInspectorTests"

echo "=== debounce, and the burst accumulator ==="
mutate "AppViewModel: ignore the debounce flag, always render immediately" "$VM" \
  's/        guard debounced else \{/        if true {/' \
  "DevelopInspectorTests"
mutate "AppViewModel: debounce drops the document update too" "$VM" \
  's/^        document = updated$/        if !debounced { document = updated }/m' \
  "DevelopInspectorTests|PreviewCutoverTests"
# Finding 1 from Task 4's review: a coalesced burst shares one developTask, so only the last call's
# flag survives to fire. Assigning instead of OR-ing loses a develop change made earlier in the burst
# and the side-by-side baseline never re-renders.
mutate "AppViewModel: the burst accumulator assigns instead of OR-ing" "$VM" \
  's/pendingDevelopChange = pendingDevelopChange \|\| developChanged/pendingDevelopChange = developChanged/' \
  "DevelopInspectorTests"
# ...and the flag describes the image being left, so it must not survive onto whatever opens next.
# **This one SURVIVED on the first run** — a real gap, not an equivalence: nothing checked that
# `load()` clears the flag, so a debounced develop edit cancelled by the next open leaked its
# pending baseline render onto the following image. Closed by
# `DevelopInspectorTests.testAPendingDevelopFlagDoesNotSurviveOpeningAnotherImage`, written for this
# mutation rather than deleting it.
mutate "AppViewModel: a pending develop flag survives onto the next image" "$VM" \
  's/^        pendingDevelopChange = false\n//m' \
  "DevelopInspectorTests"

echo "=== the histogram belongs to the Info tab ==="
mutate "AppViewModel: tally a histogram for the Develop tab too" "$VM" \
  's/        guard isInspectorPresented, inspectorTab == \.info else \{ return \}/        guard isInspectorPresented else { return }/' \
  "DevelopInspectorTests"
mutate "AppViewModel: returning to Info never recomputes" "$VM" \
  's/        didSet \{ if inspectorTab == \.info \{ updateHistogram\(\) \} \}/        didSet { }/' \
  "DevelopInspectorTests"

echo "=== the toggle immediate-write path ==="
mutate "AppViewModel: toggles pick up the 60 ms slider debounce" "$VM" \
  's/self\.updateDocument\(debounced: !control\.isToggle\)/self.updateDocument(debounced: true)/' \
  "DevelopInspectorTests"
mutate "AppViewModel: the debounce decision is inverted" "$VM" \
  's/self\.updateDocument\(debounced: !control\.isToggle\)/self.updateDocument(debounced: control.isToggle)/' \
  "DevelopInspectorTests"

echo "=== nil semantics ==="
mutate "AppViewModel: an unset white balance reads back 0" "$VM" \
  's/case \.whiteBalance: return develop\.neutralTemperature \?\? seed\?\.asShotTemperature \?\? 0/case .whiteBalance: return 0/' \
  "DevelopInspectorTests"
mutate "AppViewModel: reset writes zero instead of nil" "$VM" \
  's/            case \.exposure: document\.rawDevelop\.exposure = nil/            case .exposure: document.rawDevelop.exposure = 0/' \
  "DevelopInspectorTests"
# White balance is one control over two settings, and tint has no reset of its own.
mutate "AppViewModel: resetting white balance strands the tint" "$VM" \
  's/                document\.rawDevelop\.neutralTint = nil\n//' \
  "DevelopInspectorTests"
mutate "AppViewModel: reading a control writes the seed" "$VM" \
  's/    func developValue\(for control: DevelopControl\) -> Double \{\n        let develop = document\.rawDevelop/    func developValue(for control: DevelopControl) -> Double {\n        document.rawDevelop.exposure = document.rawDevelop.exposure ?? 0\n        let develop = document.rawDevelop/' \
  "DevelopInspectorTests"

echo "=== the is*Supported gates in apply(to:) ==="
# **The filter here is deliberately NOT the pixel test.** Removing the gate below and rerunning
# `RAWCapabilitiesTests.testAValueWrittenToAnUnsupportedAdjustmentChangesNothing` measures a worst
# pixel delta of exactly 0: `CIRAWFilter` silently discards writes to properties its decoder does
# not implement, so the framework's own gate absorbs the write whether ours ran or not. A pixel test
# cannot tell "our gate ran" from "our gate was deleted". The source-text test in
# `RAWDevelopSettingsTests` is the only thing that can, which is why it is what these three name.
mutate "RAWDevelopSettings: write an unsupported adjustment anyway" "$RD" \
  's/if let localToneMapAmount, filter\.isLocalToneMapSupported \{/if let localToneMapAmount {/' \
  "RAWDevelopSettingsTests"
mutate "RAWDevelopSettings: an adjustment gated on the wrong flag" "$RD" \
  's/if let sharpnessAmount, filter\.isSharpnessSupported \{/if let sharpnessAmount, filter.isContrastSupported {/' \
  "RAWDevelopSettingsTests"
mutate "RAWDevelopSettings: highlight recovery keeps #available but loses its flag" "$RD" \
  's/if let highlightRecoveryEnabled, #available\(macOS 26, \*\), filter\.isHighlightRecoverySupported \{/if let highlightRecoveryEnabled, #available(macOS 26, *) {/' \
  "RAWDevelopSettingsTests"

echo
echo "================ summary ================"
echo "caught:     $PASS"
echo "SURVIVED:   $SURVIVED"
echo "NO-BUILD:   $NOBUILD   (proves nothing — fix the mutation)"
echo "NO-TESTS:   $NORUN     (proves nothing — fix the filter/pattern)"
echo "SKIPPED:    $SKIPPED   (proves nothing — fixture missing; FAILS the run)"
echo "controls:   $CONTROL   (equivalent mutants — expected to survive, and did)"
[[ $CONTROL_CAUGHT -ne 0 ]] && echo "CTRL-KILL:  $CONTROL_CAUGHT   (a control was caught — a test is over-asserting; FAILS the run)"
for n in "${SURVIVOR_NAMES[@]:-}"; do [[ -n "$n" ]] && echo "  survived: $n"; done
for n in "${NOBUILD_NAMES[@]:-}"; do [[ -n "$n" ]] && echo "  no-build: $n"; done
for n in "${NORUN_NAMES[@]:-}"; do [[ -n "$n" ]] && echo "  no-tests: $n"; done
[[ $SKIPPED -eq 0 ]] || echo "  INCONCLUSIVE: $SKIPPED mutation(s) never ran — put the DNG in realworldtest/ and re-run"
for n in "${CONTROL_CAUGHT_NAMES[@]:-}"; do [[ -n "$n" ]] && echo "  control caught: $n"; done

# **SKIPPED is inconclusive, not a pass, and it belongs in this gate.** It was excluded here, which
# is the hole the failure-first classifier does not close on its own: from the summary lines alone, a
# mutation that SURVIVED in a run where any suite skipped is indistinguishable from one that merely
# skipped — both print `with N tests skipped and 0 failures` and nothing else. Excluding SKIPPED
# therefore let this harness exit 0 while proving nothing about the mutation, which is the one
# outcome a falsifiability check must never produce. An inconclusive run is not a green run: run
# this on a machine with the Leica DNG in `realworldtest/` present, or treat the result as unproven.
[[ $SURVIVED -eq 0 && $NOBUILD -eq 0 && $NORUN -eq 0 && $SKIPPED -eq 0 && $CONTROL_CAUGHT -eq 0 ]] || exit 1
