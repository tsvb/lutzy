import Foundation

/// How the preview area is divided.
///
/// Two families, and the difference is what the panels are *for*:
///
/// - `single`, `split` and `compare` are **A/B**: one picture, judged against a
///   reference. Split's reference is the ungraded original; compare's is
///   another LUT, which is the case the original cannot cover — telling two
///   near-identical film looks apart needs them next to each other, not each
///   next to the same flat baseline.
/// - The grids are a **contact sheet**: several LUTs on the same frame at once,
///   for choosing rather than for judging one.
///
/// They are one enum because they are one control: the user picks how much of
/// the screen each candidate gets, and everything else follows.
enum ComparisonLayout: String, Codable, Sendable, CaseIterable, Equatable {
    case single
    case split      // original | current LUT
    case compare    // chosen base | current LUT
    case grid1x2
    case grid2x2
    case grid3x2
    case grid3x3

    var columns: Int {
        switch self {
        case .single: return 1
        case .split, .compare, .grid1x2: return 2
        case .grid2x2: return 2
        case .grid3x2, .grid3x3: return 3
        }
    }

    var rows: Int {
        switch self {
        case .single, .split, .compare, .grid1x2: return 1
        case .grid2x2, .grid3x2: return 2
        case .grid3x3: return 3
        }
    }

    var cellCount: Int { columns * rows }

    /// Whether this layout shows a grid of independently-chosen LUTs, as
    /// opposed to an A/B pair whose two sides are decided for it.
    var isGrid: Bool {
        switch self {
        case .single, .split, .compare: return false
        case .grid1x2, .grid2x2, .grid3x2, .grid3x3: return true
        }
    }

    var label: String {
        switch self {
        case .single: return "Single"
        case .split: return "Split"
        case .compare: return "Compare"
        case .grid1x2: return "1×2"
        case .grid2x2: return "2×2"
        case .grid3x2: return "3×2"
        case .grid3x3: return "3×3"
        }
    }

    var symbol: String {
        switch self {
        case .single: return "rectangle"
        case .split: return "rectangle.split.2x1"
        case .compare: return "arrow.left.arrow.right.square"
        case .grid1x2: return "rectangle.split.2x1.fill"
        case .grid2x2: return "square.grid.2x2"
        case .grid3x2: return "square.grid.3x2"
        case .grid3x3: return "square.grid.3x3"
        }
    }
}
