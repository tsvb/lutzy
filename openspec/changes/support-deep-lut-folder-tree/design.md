## Context

The scanner already keeps complete relative paths and the hierarchy model already derives parent nodes. The previous sidebar delegated rendering to nested `DisclosureGroup` labels, which made the disclosure triangle and folder button compete for the same row and expanded every branch by default.

## Goals / Non-Goals

**Goals:**

- Preserve every path component without a product-defined depth limit.
- Make expand/collapse independent from selecting the folder's LUT scope.
- Keep a deep restored selection visible.
- Make ancestry readable without adding visual noise to the colour workstation.

**Non-Goals:**

- Moving, creating, renaming, or deleting folders.
- Smart collections or tag groups.
- Showing LUT files inside the folder tree.
- Persisting every disclosure toggle across launches.

## Decisions

### Recursive branch view

Each `LUTFolderNode` renders one row and recursively renders its children. No switch or fixed list of depths exists. The file system remains the practical path-length limit.

### Separate controls

Branches with children receive an 18-point disclosure target followed by a full-width folder selection target. Clicking the chevron changes only disclosure; clicking the folder changes only the contact-sheet scope.

### Progressive disclosure

Top-level packages open initially so their organisation is discoverable. Deeper branches stay collapsed unless they contain the restored selection. When selection moves into a hidden descendant, each ancestor opens to reveal it.

### Workstation hierarchy treatment

Native typography and the existing accent selection remain. A one-pixel low-contrast vertical rail is the sole new visual device; it follows the folder lineage and prevents repeated indentation from reading as unrelated rows.

## Risks / Trade-offs

- **A deeply nested name eventually has less horizontal space.** → Keep indentation to 14 points per level and use middle truncation/tooltips for complete paths.
- **Opening all packages could still be dense.** → Only top-level branches default open; deeper branches remain compact.
- **Selection could be hidden after session restore.** → Initialize and update ancestor disclosure from exact-or-descendant path membership.

## Migration Plan

No migration is required. Existing category paths and saved `browsedCategory` values are reused.

## Open Questions

None.
