## ADDED Requirements

### Requirement: Explicit grid assignment target
Every comparison grid SHALL expose exactly one active assignment cell and SHALL default to the first cell when no valid target exists.

#### Scenario: Enter a grid
- **WHEN** the user changes from a non-grid layout to 2×2 or 3×3
- **THEN** Cell 1 is visibly marked as the active assignment target

#### Scenario: Activate another cell
- **WHEN** the user clicks a comparison cell
- **THEN** that cell becomes the sole active target and its LUT becomes the current inspector selection

#### Scenario: Reopen a saved grid
- **WHEN** a saved grid's selected LUT matches one of its cells
- **THEN** that matching cell becomes the active target, with Cell 1 used only when no match exists

### Requirement: Assign from the visual contact sheet
Grid layouts SHALL use the lower LUT contact sheet instead of a per-cell LUT dropdown.

#### Scenario: Click a LUT card
- **WHEN** a grid is visible and the user clicks a LUT card
- **THEN** the active cell is replaced with that LUT and neighbouring cells remain unchanged

#### Scenario: Cycle LUTs from the keyboard
- **WHEN** a grid is visible and the user invokes next or previous LUT
- **THEN** the resulting LUT replaces the active cell just like a contact-sheet click

#### Scenario: Drag a LUT card
- **WHEN** the user drags a LUT card onto any grid cell
- **THEN** the drop cell is replaced with that LUT, becomes active, and neighbouring cells remain unchanged

#### Scenario: Hover a valid drop destination
- **WHEN** a LUT card is held over a grid cell
- **THEN** that cell shows a numbered replacement prompt and emphasized boundary

### Requirement: Preserve non-grid gallery behaviour
The LUT contact sheet SHALL continue to apply a clicked LUT to the main preview whenever the active layout is not a comparison grid.

#### Scenario: Click a card in Single view
- **WHEN** the user clicks a LUT card in Single view
- **THEN** the main preview applies the LUT and stored comparison-cell assignments remain unchanged

### Requirement: Isolated cell rendering
Assigning a LUT through click or drag SHALL re-render only the changed grid cell.

#### Scenario: Replace one cell
- **WHEN** one grid cell receives a different LUT
- **THEN** every other cell retains its LUT assignment and render task
