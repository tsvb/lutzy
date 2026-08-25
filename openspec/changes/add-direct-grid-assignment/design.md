## Context

The Viewer now has a folder-scoped visual LUT contact sheet below the preview. Grid cells still use an older text-menu picker, forcing users to switch from judging rendered images to scanning repeated filename lists.

## Goals / Non-Goals

**Goals:**

- Make the lower visual gallery the single LUT picker for 1×2, 2×2, 3×2, and 3×3 grids.
- Support a fast keyboard/pointer-friendly click path and a spatial drag path.
- Keep the active assignment destination unmistakable.
- Re-render only the cell whose LUT changed.

**Non-Goals:**

- Reordering cells by drag.
- Persisting pointer focus in project files.
- Changing A/B layouts, LUT Manager, LUT Editor, or colour processing.

## Decisions

### One transient active target

Entering a grid activates Cell 1 unless an existing valid target remains. When a grid session is reopened, its last selected LUT reconnects focus to the matching cell; Cell 1 remains the fallback. Clicking a cell activates it and synchronises the selected LUT used by the inspector. A blue border, numbered label, and target icon expose the state without adding another control.

### Click and drag are complementary

Clicking a lower LUT card assigns it to the active cell. Dragging the card carries only the LUT's stable string ID and assigns it to the cell where it is dropped, regardless of which cell was active before. The accepted drop cell becomes active.

### Gallery semantics depend on layout family

Grid layouts interpret a card click as cell assignment. Single and A/B layouts retain the existing behaviour of applying the card to the main preview. Leaving the grid clears transient cell focus.

Keyboard LUT cycling follows the same rule as a card click, so it cannot leave the selected card and active cell describing different looks.

### Keep rendering isolated

Both interaction paths update one `cellLUTIDs` entry and invoke `renderCell` for that index. Neighbouring assignments and renders are not rebuilt.

## Risks / Trade-offs

- **Users may not know where a card click will go.** → Show `Assigning to Cell N` beside the folder name and outline the target cell.
- **Drag targets can be ambiguous in a dense 3×3.** → Tint the hovered cell and show `Drop to replace Cell N` before acceptance.
- **Removing the menu removes its explicit Original item.** → Keep `Show Original in Cell N` in the cell context menu.

## Migration Plan

No data migration is required. Existing saved cell LUTs restore unchanged; the cell containing the saved selection becomes the target, with Cell 1 as fallback.

## Open Questions

None.
