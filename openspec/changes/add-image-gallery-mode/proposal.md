## Why

The project image manager currently offers only a dense table. Users need both a list for filenames and folders and a visual gallery for identifying and selecting photographs by appearance.

## What Changes

- Add an Images presentation control with List and Gallery modes.
- Keep the current table as List mode.
- Add a responsive thumbnail gallery with clear selected, loading, and empty states.
- Preserve selection, open, export-selected, and remove actions across both modes.
- Remember the chosen presentation between visits.

## Capabilities

### New Capabilities

- `image-manager-presentation`: Defines the List/Gallery switch, gallery selection behaviour, and parity of image-management actions.

### Modified Capabilities

None.

## Impact

The change primarily affects `ImageManagerView` and may add a small presentation-state model plus focused tests. It does not change project storage, image import, rendering, or export formats.
