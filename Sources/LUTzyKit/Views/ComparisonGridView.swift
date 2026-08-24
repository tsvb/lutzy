import SwiftUI

/// Several LUTs on the same frame at once — a contact sheet for choosing.
///
/// Each cell is independently assignable and independently rendered. The cell
/// is the control: clicking it adopts its LUT as the selection (the move from
/// surveying to working), and its menu re-assigns it without disturbing the
/// others.
struct ComparisonGridView: View {
    @ObservedObject var viewModel: AppViewModel

    private let bgColor = Color(nsColor: NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1))

    var body: some View {
        let layout = viewModel.comparisonLayout
        // A fixed grid, not an adaptive one: the user asked for 3×3, so it is
        // 3×3 at every window size. Cells get smaller; they do not re-flow.
        VStack(spacing: 2) {
            ForEach(0..<layout.rows, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<layout.columns, id: \.self) { column in
                        let index = row * layout.columns + column
                        if index < viewModel.cellLUTIDs.count {
                            cell(index)
                        } else {
                            bgColor
                        }
                    }
                }
            }
        }
        .padding(8)
    }

    private func cell(_ index: Int) -> some View {
        let lut = viewModel.cellLUTs[index]
        let isSelected = lut?.lutID == viewModel.selectedLUT?.lutID

        return ZStack(alignment: .bottom) {
            bgColor

            if let image = viewModel.cellImages[index] {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView().controlSize(.small)
            }

            CellLabel(
                name: lut?.name ?? "No LUT",
                isSelected: isSelected,
                choose: { viewModel.setCell(index, to: $0) },
                luts: viewModel.library.allLUTs
            )
            .padding(6)
        }
        .clipped()
        .overlay(
            // The selection ring is the only thing distinguishing the cell the
            // inspector is describing from the eight it is not.
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture { viewModel.adoptCell(index) }
    }
}

/// A cell's name plate, which is also its LUT picker.
///
/// One control rather than a label plus a button: the name is what the user is
/// reading when they decide to change it, so it is what they should be able to
/// click.
private struct CellLabel: View {
    let name: String
    let isSelected: Bool
    let choose: (CubeLUT?) -> Void
    let luts: [CubeLUT]

    var body: some View {
        Menu {
            Button("No LUT") { choose(nil) }
            Divider()
            ForEach(luts) { lut in
                Button(lut.name) { choose(lut) }
            }
        } label: {
            Text(name)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}
