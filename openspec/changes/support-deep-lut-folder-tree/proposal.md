## Why

LUT collections are commonly organised as packages containing camera families, profiles, vendors, and individual look sets. Treating that structure as one or two fixed levels either flattens meaningful organisation or makes large libraries open as an overwhelming list.

## What Changes

- Render every component of a LUT's relative folder path as a recursive Viewer folder row.
- Separate disclosure from folder selection so expanding a package does not change the contact sheet.
- Open top-level packages initially, keep deeper branches compact, and reveal the ancestors of a restored selection.
- Add subtle branch rails and recursive roll-up counts for deep-tree readability.
- Add focused verification with a twelve-level fixture to prevent a fixed-depth regression.

## Capabilities

### New Capabilities

- `deep-lut-folder-tree`: Defines arbitrary nesting, disclosure behaviour, selection visibility, and recursive counts.

### Modified Capabilities

None.

## Impact

This affects only Viewer's folder navigation and its hierarchy checks. LUT paths, files, Manager, Editor, and the contact-sheet colour pipeline remain unchanged.
