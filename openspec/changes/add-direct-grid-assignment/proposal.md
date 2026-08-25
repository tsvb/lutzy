## Why

Comparison grids currently repeat the entire LUT library in a dropdown on every cell. The lower contact sheet already communicates each LUT visually, so searching a text menu inside a 2×2 or 3×3 is slower and disconnected from the comparison task.

## What Changes

- Give every comparison grid one visible active assignment cell.
- Replace a grid cell by clicking a LUT card in the lower contact sheet.
- Allow a LUT card to be dragged directly onto any comparison cell.
- Remove the per-cell LUT dropdown while preserving a compact cell/LUT label.
- Keep ordinary contact-sheet clicks applying to the main preview outside grid layouts.

## Capabilities

### New Capabilities

- `direct-grid-assignment`: Defines target selection, click assignment, drag assignment, and non-grid fallback behaviour.

### Modified Capabilities

None.

## Impact

This changes Viewer comparison interaction and transient view-model focus. It does not change LUT files, project schema, rendering maths, or LUT Manager and LUT Editor behaviour.
