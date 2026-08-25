## Why

Viewer currently lists individual LUT files in its navigation column and shows only the selected result at useful size. A large library is easier to understand by its existing folder hierarchy, and choosing a look is faster when every LUT in that folder can be judged on the same photograph at once.

## What Changes

- Give Viewer a folder-only hierarchical LUT navigation column.
- Make parent-folder selection include LUTs in every descendant folder.
- Place a lazily rendered LUT contact sheet below the main Viewer preview.
- Apply a LUT when its card is selected and expose favourite/reveal actions on each card.
- Keep the existing dense LUT list in LUT Manager and LUT Editor, where file and metadata work still benefits from it.

## Capabilities

### New Capabilities

- `viewer-folder-contact-sheet`: Defines folder aggregation, Viewer layout, rendering consistency, and LUT-card interaction.

### Modified Capabilities

None.

## Impact

This adds a folder hierarchy model, a Viewer folder column, a LUT preview gallery, lazy preview rendering through `RenderEngine`, focused checks, and Viewer navigation documentation. It does not move or rename LUT files.
