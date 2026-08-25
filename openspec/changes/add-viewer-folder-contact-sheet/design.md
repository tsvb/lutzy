## Context

The LUT scan already preserves complete relative directory paths such as `Sony/VENICE/Creative`, but the current sidebar treats each complete path as a flat category and mixes those categories with individual LUT rows. Viewer therefore spends its navigation space on filenames while offering no persistent contact sheet for visual comparison.

The reference interface establishes a useful division: folders on the left, one large judged image above, and all candidate LUT renders below. LUT Manager remains a different job and should retain its table and bulk actions.

## Goals / Non-Goals

**Goals:**

- Let a user navigate LUTs by their on-disk folder hierarchy in Viewer.
- Treat selecting a parent folder as selecting its entire subtree.
- Render visible LUT cards through the same document and engine as the main preview.
- Keep the contact sheet responsive with lazy view creation and cancellable tasks.
- Make card size adjustable without changing folder selection.

**Non-Goals:**

- Moving, renaming, or restructuring LUT files.
- Replacing LUT Manager's table or bulk operations.
- Creating a second colour pipeline or storing baked LUT thumbnails.
- Removing Viewer comparison layouts or its image filmstrip.

## Decisions

### Reconstruct hierarchy from category paths

The scanner remains unchanged and continues publishing full category paths. `LUTFolderHierarchy` derives ancestor nodes and recursive counts in memory. A category belongs to a selected folder only when it is the same path or begins with the selected path followed by `/`, preventing `Sony` from accidentally matching `Sony Pictures`.

### Viewer owns the visual contact sheet

Viewer uses a vertical split: the existing preview and filmstrip above, an adaptive LUT gallery below. The divider is user-resizable. The primary navigation and Viewer-owned Images surface remain unchanged.

### One rendering path

Every LUT card copies the current `EditDocument`, substitutes only the candidate LUT, and calls the existing `RenderEngine`. RAW development, pre-LUT adjustments, source-space handling, and LUT intensity therefore agree with the main preview. Cards render only when their lazy-grid views exist and their tasks cancel when the card leaves the view.

### Separate selection from invalidation

Selecting a card updates the main LUT but does not invalidate every contact-sheet render. A gallery revision changes only when the source image, adjustments, intensity, source-space choice, or scanned LUT data changes.

## Risks / Trade-offs

- **A folder can contain hundreds of descendant LUTs.** → Use `LazyVGrid`, small preview targets, and cancellable per-card tasks.
- **Recursive counts could disagree with selection.** → Derive both from the same exact-or-descendant predicate and cover it with focused tests.
- **Viewer becomes vertically dense.** → Use a resizable split and preserve the existing image filmstrip at a reduced height.
- **Contact-sheet colours could drift from the main image.** → Route both through the same renderer and document instead of a thumbnail-specific colour implementation.

## Migration Plan

No data migration is required. Existing folder paths and saved `browsedCategory` values remain valid. The contact-sheet card width is a new display preference with a conservative default.

## Open Questions

None.
