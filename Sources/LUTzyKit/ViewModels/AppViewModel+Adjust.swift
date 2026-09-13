import SwiftUI

/// `AppViewModel`'s adjustment bindings — Step 10b.
///
/// Deliberately thin. Every one of these forwards to a pure function on `AdjustmentControl` and then
/// re-renders; none of them knows how the sparse array is shaped. That is what lets the whole
/// contract be tested without a view model, an engine or a GPU — see `AdjustmentControlTests`.
extension AppViewModel {

    /// What a row should display, in **slider space**.
    ///
    /// **Reading never writes**, the same property `developBinding(for:)` has: an absent node reads
    /// as the control's neutral rather than being seeded into the document. Seeding on open would
    /// make every document non-neutral the moment the panel was looked at, which would in turn make
    /// the A/B comparison offer itself on an untouched image.
    func adjustmentValue(for control: AdjustmentControl) -> Double {
        control.sliderMapped(control.value(in: document.adjustments))
    }

    /// A two-way binding for one row. Slider space on both sides — `sliderMapped` is self-inverse,
    /// so the same call converts each way.
    ///
    /// **Debounced**, because every row here is a continuous control: there are no toggles in this
    /// panel, unlike Develop's three.
    func adjustmentBinding(for control: AdjustmentControl) -> Binding<Double> {
        Binding(
            get: { self.adjustmentValue(for: control) },
            set: { newValue in
                self.updateDocument(debounced: true) { document in
                    document.adjustments = control.setting(
                        control.sliderMapped(newValue), in: document.adjustments
                    )
                }
            }
        )
    }

    /// Return one row to its neutral. Undebounced — `updateDocument(debounced:)`'s contract is that
    /// discrete controls fire immediately.
    func resetAdjustment(_ control: AdjustmentControl) {
        updateDocument { document in
            document.adjustments = control.setting(control.neutral, in: document.adjustments)
        }
    }

    /// Return every row to its neutral.
    ///
    /// Clears `adjustments` and nothing else: `rawDevelop` and the LUT belong to other panels, and a
    /// Reset button that reached across panel boundaries would be a trap.
    func resetAllAdjustments() {
        updateDocument { $0.adjustments = [] }
    }

    /// Whether any row is off its neutral — the Reset button's enabled state.
    ///
    /// Not `!document.adjustments.isEmpty` — that would have been correct only because the array is
    /// sparse (`AdjustmentControl.setting(_:in:)` never stores an identity node, which
    /// `AdjustmentControlTests` pins), and `isComparisonAvailable` in `AppViewModel.swift` gave up
    /// that same shortcut for the same reason: it does not depend on the sparse invariant holding for
    /// a document that arrived by decoding rather than by a slider write. Today the two properties
    /// would agree either way; Step 11's undo path is what makes them diverge, so this is written to
    /// match now rather than after that lands.
    var hasAdjustments: Bool { !document.adjustments.allSatisfy(\.isIdentity) }

    /// Whether any control in one Adjust-panel section is off its neutral — that section's own
    /// Reset button's enabled state. `AdjustmentGroup.allCases` will not silently miss a new
    /// section, since `hasAdjustments` above already establishes what "off neutral" means for a
    /// single control.
    func hasAdjustments(in group: AdjustmentGroup) -> Bool {
        AdjustmentControl.allCases
            .filter { $0.group == group }
            .contains { adjustmentValue(for: $0) != $0.neutral }
    }
}
