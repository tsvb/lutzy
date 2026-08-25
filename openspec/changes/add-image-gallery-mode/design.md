## Context

`ImageManagerView` owns one selection set and exposes Open, Export Selected, and Remove actions through a macOS `Table`. The same images already have asynchronously generated `NSImage` thumbnails. Gallery mode can therefore be a second presentation over the existing rows and selection, without changing project storage or image loading.

The visual direction stays native and utilitarian: filenames and folder context remain available, while the photograph becomes the dominant recognition target. The distinctive element is a quiet film-contact-sheet rhythm built from consistent thumbnail cards, not a new colour palette or decorative layer.

## Goals / Non-Goals

**Goals:**

- Switch between List and Gallery without rebuilding or reimporting images.
- Preserve the current selection and all image-management actions.
- Make Gallery responsive to window width and useful with missing thumbnails.
- Remember the chosen presentation.
- Keep mouse, keyboard, and accessibility semantics understandable.

**Non-Goals:**

- Editing image metadata or project folder structure.
- Adding a third project-image presentation.
- Replacing the viewer filmstrip.
- Changing thumbnail generation or export behaviour.

## Decisions

### One shared row and selection model

List and Gallery render the same `[Row]` and mutate the same `Set<String>`. Switching presentation therefore preserves selection by construction. The existing action bar remains shared below both presentations.

Alternative: give each mode independent selection. Rejected because switching would silently change the export/remove target.

### Persisted native mode control

A compact segmented picker labelled for accessibility sits above the presentation, using `list.bullet` and `square.grid.2x2` symbols. The value is stored with `@AppStorage`, defaulting to List so existing users see no surprise on first launch.

### Adaptive contact-sheet gallery

Gallery uses `ScrollView` and an adaptive `LazyVGrid`. Cards show a large aspect-fill thumbnail, filename, and optional subfolder. Selected cards use a clear accent outline and selection tint; missing thumbnails use a stable placeholder of the same size so layout does not jump.

### Finder-like selection

A plain click selects one image, Command-click toggles an image, and Shift-click selects a contiguous range from the last anchor. Double-click opens the selected image in Viewer. Context-menu actions match List mode.

The selection calculation is a small pure helper so modifier and range behaviour can be unit-tested without rendering SwiftUI.

## Risks / Trade-offs

- **Single and double tap gestures can both fire.** → Make selection idempotent before opening and keep the open action bound to the clicked row.
- **Very large libraries can create excessive view work.** → Use `LazyVGrid` and existing thumbnails; do not decode full-resolution images in the card.
- **Modifier state can be unavailable to keyboard activation.** → Plain keyboard activation selects one row; Command/Shift semantics apply to pointer selection and are exposed through the pure selection helper.
- **Filename-based IDs can collide if project import semantics change.** → Reuse the current table ID for this change; changing project identity is a separate migration.

## Migration Plan

No data migration is required. The persisted preference is new and defaults to List. Removing the feature leaves project files untouched.

## Open Questions

None.
