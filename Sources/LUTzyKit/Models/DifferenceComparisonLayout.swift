import CoreGraphics

/// User-visible regions in Difference mode. A and B stay visible beside the
/// amplified map so the map never loses the pictures that explain it.
enum DifferenceRegion: String, CaseIterable, Identifiable, Sendable {
    case a
    case b
    case difference

    var id: String { rawValue }
}

enum DifferenceComparisonLayout {
    /// A and B share the narrower left column; Difference spans the full right
    /// side. Returned frames use top-left coordinates, matching SwiftUI's
    /// visual layout once positioned by each rectangle's midpoint.
    static func frames(
        in size: CGSize,
        spacing: CGFloat = 2
    ) -> [DifferenceRegion: CGRect] {
        let safeSpacing = max(0, spacing)
        let availableWidth = max(0, size.width - safeSpacing)
        let availableHeight = max(0, size.height - safeSpacing)
        let referenceWidth = availableWidth / 3
        let differenceWidth = availableWidth - referenceWidth
        let referenceHeight = availableHeight / 2

        return [
            .a: CGRect(x: 0, y: 0, width: referenceWidth, height: referenceHeight),
            .b: CGRect(
                x: 0,
                y: referenceHeight + safeSpacing,
                width: referenceWidth,
                height: referenceHeight
            ),
            .difference: CGRect(
                x: referenceWidth + safeSpacing,
                y: 0,
                width: differenceWidth,
                height: size.height
            ),
        ]
    }
}
