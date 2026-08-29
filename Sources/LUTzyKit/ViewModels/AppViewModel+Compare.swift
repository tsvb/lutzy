import Foundation
import AppKit
import CoreGraphics

/// The comparison grid: several LUTs on the same frame at once.
///
/// Split out from `AppViewModel` for size, the way `+Develop` was. The state is
/// small — a layout, one LUT per cell, one rasterized image per cell — but the
/// rendering has a rule worth stating: **cells render independently and
/// cancel independently**. A 3×3 is nine renders, and re-picking one cell must
/// cost one of them, not nine. Anything that invalidates the frame itself (a
/// new image, a develop change, an adjustment) is the exception and reloads all
/// of them.
@MainActor
extension AppViewModel {

    // MARK: - Layout

    /// Switch layout. Grids fill themselves the first time they are shown.
    func setLayout(_ layout: ComparisonLayout) {
        guard layout != comparisonLayout else {
            ensureActiveGridCell()
            return
        }
        let wasGrid = comparisonLayout.isGrid
        comparisonLayout = layout
        isSideBySide = layout == .split
        if layout.isGrid || layout.hasChosenBase {
            fitCells(to: layout)
            renderAllCells()
        }
        ensureActiveGridCell()
        if wasGrid, layout.isGrid == false {
            // Grid assignments intentionally leave the hidden full-size
            // preview stale. Materialize it once when it becomes visible
            // again instead of once per cell selection.
            refreshMainPreviewAfterGrid()
        }
    }

    /// Resize the cell list to the layout, keeping what was already chosen.
    ///
    /// Growing pulls further LUTs from the library rather than leaving holes: a
    /// contact sheet that opens empty asks the user to do nine pickings before
    /// it shows anything, and the point of it is to survey a library quickly.
    /// Shrinking keeps the first cells, so 3×3 → 2×2 is a crop, not a reshuffle.
    private func fitCells(to layout: ComparisonLayout) {
        synchronizeComparisonCellStorage()
        let wanted = layout.hasChosenBase ? 1 : layout.cellCount
        if cellLUTIDs.count > wanted {
            cellLUTIDs = Array(cellLUTIDs.prefix(wanted))
            cellImages = Array(cellImages.prefix(wanted))
            ensureActiveGridCell()
            return
        }
        guard cellLUTIDs.count < wanted else { return }

        // Fill from the library, starting at the current selection and skipping
        // anything already on screen.
        var used = Set(cellLUTIDs.compactMap { $0 })
        var pool = library.allLUTs.map(\.lutID)
        if let current = selectedLUT?.lutID, let start = pool.firstIndex(of: current) {
            pool = Array(pool[start...]) + Array(pool[..<start])
        }
        var next = pool.makeIterator()
        while cellLUTIDs.count < wanted {
            guard let candidate = next.next() else {
                cellLUTIDs.append(nil)          // library exhausted: show the original
                cellImages.append(nil)
                continue
            }
            guard used.contains(candidate) == false else { continue }
            used.insert(candidate)
            cellLUTIDs.append(candidate)
            cellImages.append(nil)
        }
    }

    // MARK: - Cells

    /// The LUTs on screen, in cell order. `nil` means "no LUT" — the ungraded
    /// picture, which is a legitimate thing to want a slot for.
    var cellLUTs: [CubeLUT?] {
        cellLUTIDs.map { id in id.flatMap { lutForCell($0) } }
    }

    /// What compare, wipe and diff judge against. The other side is always the
    /// current selection, so the base is the only thing to choose.
    var compareBaseLUT: CubeLUT? { cellLUTIDs.first.flatMap { $0 }.flatMap { lutForCell($0) } }

    private func lutForCell(_ id: LUTID) -> CubeLUT? {
        library.allLUTs.first(matching: id)
    }

    /// Put a LUT in one cell and re-render only that cell.
    func setCell(_ index: Int, to lut: CubeLUT?) {
        guard cellLUTIDs.indices.contains(index) else { return }
        guard cellLUTIDs[index] != lut?.lutID else { return }
        cellLUTIDs[index] = lut?.lutID
        renderCell(index)
    }

    /// Make a grid cell the receiver for the next LUT-card click and keep the
    /// inspector in sync with what that cell contains.
    func activateGridCell(_ index: Int) {
        guard comparisonLayout.isGrid, cellLUTIDs.indices.contains(index) else { return }
        activeGridCellIndex = index
        selectLUT(
            cellLUTIDs[index].flatMap { lutForCell($0) },
            renderPreview: false,
            renderGridCells: false
        )
    }

    /// Ensure every visible grid has a usable click target. Restored sessions
    /// predate this transient focus state, so the first cell is the predictable
    /// default rather than requiring a preparatory click.
    func ensureActiveGridCell() {
        guard comparisonLayout.isGrid, cellLUTIDs.isEmpty == false else {
            activeGridCellIndex = nil
            return
        }
        if let activeGridCellIndex, cellLUTIDs.indices.contains(activeGridCellIndex) {
            return
        }
        activeGridCellIndex = 0
    }

    /// Apply a LUT-card click. In a grid the active cell is replaced; in every
    /// other Viewer layout the card keeps its ordinary main-preview behaviour.
    func chooseLUTFromGallery(_ lut: CubeLUT) {
        guard comparisonLayout.isGrid else {
            selectLUT(lut)
            return
        }
        ensureActiveGridCell()
        guard let index = activeGridCellIndex else { return }
        assignGridCell(index, to: lut)
    }

    /// Assign an explicit drop destination. The raw stable ID is the drag
    /// payload, keeping the UI transfer small even for a 65-cube LUT.
    @discardableResult
    func assignDraggedLUT(rawID: String, to index: Int) -> Bool {
        guard comparisonLayout.isGrid,
              cellLUTIDs.indices.contains(index),
              let lut = library.allLUTs.first(matching: LUTID(raw: rawID))
        else { return false }
        assignGridCell(index, to: lut)
        return true
    }

    /// Replace one target and select the same look for the inspector without
    /// disturbing neighbouring cells.
    func assignGridCell(_ index: Int, to lut: CubeLUT?) {
        guard comparisonLayout.isGrid, cellLUTIDs.indices.contains(index) else { return }
        activeGridCellIndex = index
        setCell(index, to: lut)
        selectLUT(lut, renderPreview: false, renderGridCells: false)
    }

    /// Backwards-compatible name for callers that treat a cell click as
    /// adopting its LUT.
    func adoptCell(_ index: Int) {
        activateGridCell(index)
    }

    // MARK: - Rendering

    /// Re-render every cell. Called when the frame itself changed.
    func renderAllCells() {
        guard comparisonLayout.isGrid || comparisonLayout.hasChosenBase else { return }
        synchronizeComparisonCellStorage()
        for index in cellLUTIDs.indices { renderCell(index) }
    }

    /// Keep the render slots index-parallel with the chosen LUT slots.
    ///
    /// Session restoration and library identity migration can publish the LUT
    /// IDs before a frame is available. A render scheduled in that short
    /// window must grow the image storage instead of indexing a stale array.
    func synchronizeComparisonCellStorage() {
        if cellImages.count > cellLUTIDs.count {
            cellImages = Array(cellImages.prefix(cellLUTIDs.count))
        } else if cellImages.count < cellLUTIDs.count {
            cellImages.append(contentsOf: repeatElement(nil, count: cellLUTIDs.count - cellImages.count))
        }
    }

    /// Render one cell.
    ///
    /// The cell is rendered at the size it is actually shown at, not at the full
    /// preview box: a 3×3 cell is a ninth of the area, and rendering nine
    /// full-size previews to display them thumbnail-size is eight ninths of the
    /// work thrown away. The floor keeps a 3×3 cell from becoming too coarse to
    /// judge a look by.
    func renderCell(_ index: Int) {
        synchronizeComparisonCellStorage()
        guard cellLUTIDs.indices.contains(index), cellImages.indices.contains(index), let imageSource else { return }
        cellTasks[index]?.cancel()

        // A chosen-base change is the other half of the same pairing rule as
        // `prepareDifferencePreviewRender`: never leave the previous A available for a new B.
        if comparisonLayout == .diff {
            cellImages[index] = nil
            diffNSImage = nil
        }

        let lut = cellLUTIDs[index].flatMap { lutForCell($0) }
        var request = document
        request.lut.lutID = lut?.lutID
        let box = cellBox

        cellTasks[index] = Task(priority: .userInitiated) { [engine] in
            let cgImage = await engine.makeCGImage(
                source: imageSource, document: request, lut: lut,
                scale: .preview(maxSize: box), space: .current
            )
            guard !Task.isCancelled, let cgImage else { return }
            guard self.cellImages.indices.contains(index) else { return }
            self.cellImages[index] = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
            self.refreshDifference()
        }
    }

    /// Rebuild the difference image, if that is what is on screen.
    ///
    /// Called from both sides — the main preview and the base cell land
    /// independently, and whichever arrives second is the one that completes
    /// the pair. Cheap enough to redo on each: it is one kernel over a
    /// preview-sized image.
    func refreshDifference() {
        guard comparisonLayout == .diff else {
            if diffNSImage != nil { diffNSImage = nil }
            return
        }
        diffNSImage = DifferenceComposer.compose(
            base: cellImages.first ?? nil,
            graded: previewNSImage
        )
    }

    /// Clear every Difference input that the next preview scheduling pass will replace.
    ///
    /// Kept as a small internal seam so the out-of-order completion contract can be checked by
    /// `lutcheck` without making a renderer deliberately slow. When `rerenderBase` is true both
    /// tasks belong to the same visual generation, so neither old side may survive into it.
    func prepareDifferencePreviewRender(rerenderBase: Bool) {
        guard comparisonLayout == .diff else { return }
        previewNSImage = nil
        diffNSImage = nil
        if rerenderBase, cellImages.indices.contains(0) {
            cellImages[0] = nil
        }
    }

    /// The render size for one cell of the current layout.
    private var cellBox: CGSize {
        // Wipe overlays the two and difference subtracts them, so in both the
        // base has to come out the same size as the main preview — a cell
        // rendered smaller could not be subtracted at all.
        guard comparisonLayout.isGrid else { return maxPreview }
        let divisor = CGFloat(max(comparisonLayout.columns, comparisonLayout.rows))
        let floor: CGFloat = 420
        return CGSize(
            width: max(maxPreview.width / divisor, floor),
            height: max(maxPreview.height / divisor, floor * 0.75)
        )
    }
}
