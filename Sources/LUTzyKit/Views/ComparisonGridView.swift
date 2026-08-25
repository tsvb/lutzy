import SwiftUI

/// Several LUTs on the same frame at once — a contact sheet for choosing.
///
/// A click makes one cell the target for the lower LUT gallery. A drag can
/// bypass that focus and replace any cell directly. The visual gallery is the
/// picker; repeating the whole library in nine menus made a 3×3 slower to use
/// precisely when it was meant to make comparison faster.
struct ComparisonGridView: View {
    @ObservedObject var viewModel: AppViewModel

    private let bgColor = Color(nsColor: NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1))

    var body: some View {
        let layout = viewModel.comparisonLayout
        // A fixed grid, not an adaptive one: 3×3 remains 3×3 at every window
        // size. Cells get smaller; they do not silently re-flow.
        VStack(spacing: 2) {
            ForEach(0..<layout.rows, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<layout.columns, id: \.self) { column in
                        let index = row * layout.columns + column
                        if index < viewModel.cellLUTIDs.count {
                            ComparisonGridCell(
                                index: index,
                                viewModel: viewModel,
                                background: bgColor
                            )
                        } else {
                            bgColor
                        }
                    }
                }
            }
        }
        .padding(8)
        .onAppear { viewModel.ensureActiveGridCell() }
    }
}

private struct ComparisonGridCell: View {
    let index: Int
    @ObservedObject var viewModel: AppViewModel
    let background: Color

    @State private var isDropTargeted = false

    private var lut: CubeLUT? {
        guard viewModel.cellLUTs.indices.contains(index) else { return nil }
        return viewModel.cellLUTs[index]
    }

    private var image: NSImage? {
        guard viewModel.cellImages.indices.contains(index) else { return nil }
        return viewModel.cellImages[index]
    }

    private var isActive: Bool { viewModel.activeGridCellIndex == index }

    var body: some View {
        ZStack {
            background

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView().controlSize(.small)
            }

            if isDropTargeted {
                Color.accentColor.opacity(0.13)
                VStack(spacing: 7) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.title2)
                    Text("Drop to replace Cell \(index + 1)")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { viewModel.activateGridCell(index) }
        .dropDestination(for: String.self) { rawIDs, _ in
            guard let rawID = rawIDs.first else { return false }
            return viewModel.assignDraggedLUT(rawID: rawID, to: index)
        } isTargeted: {
            isDropTargeted = $0
        }
        .overlay(alignment: .bottomLeading) {
            cellPlate
                .padding(7)
                .allowsHitTesting(false)
        }
        .clipped()
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    isActive || isDropTargeted ? Color.accentColor : .clear,
                    lineWidth: isDropTargeted ? 3 : 2
                )
        }
        .contextMenu {
            Button("Show Original in Cell \(index + 1)") {
                viewModel.assignGridCell(index, to: nil)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cell \(index + 1), \(lut?.name ?? "Original")")
        .accessibilityValue(isActive ? "Active assignment target" : "")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { viewModel.activateGridCell(index) }
    }

    private var cellPlate: some View {
        HStack(spacing: 7) {
            Text("CELL \(index + 1)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(isActive ? Color.accentColor : Color.white.opacity(0.7))

            Rectangle()
                .fill(Color.white.opacity(0.24))
                .frame(width: 1, height: 11)

            Text(lut?.name ?? "Original")
                .font(.caption.weight(isActive ? .semibold : .regular))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)

            if isActive {
                Image(systemName: "scope")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 6))
    }
}
