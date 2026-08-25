## ADDED Requirements

### Requirement: Hierarchical Viewer folder navigation
Viewer SHALL present LUT organisation as a folder hierarchy and SHALL keep individual LUT files out of the folder navigation column.

#### Scenario: Select a leaf folder
- **WHEN** the user selects a leaf LUT folder
- **THEN** the contact sheet contains every LUT directly inside that folder

#### Scenario: Select a parent folder
- **WHEN** the user selects a folder that contains descendant folders
- **THEN** the contact sheet contains LUTs directly inside the parent and every descendant folder

#### Scenario: Similar folder prefixes
- **WHEN** folders named `Sony` and `Sony Pictures` both exist and the user selects `Sony`
- **THEN** LUTs from `Sony Pictures` are not included

### Requirement: Preview and contact-sheet layout
Viewer SHALL place the main image preview above a resizable LUT contact sheet and SHALL preserve its image filmstrip when multiple images are loaded.

#### Scenario: Resize the Viewer regions
- **WHEN** the user drags the divider between the main preview and LUT contact sheet
- **THEN** both regions remain usable within their minimum heights

### Requirement: Consistent LUT-card rendering
Each visible LUT card SHALL render the current source image through the same document and rendering engine as the main preview, substituting only the candidate LUT.

#### Scenario: Apply pre-LUT adjustments
- **WHEN** the user changes source development, adjustments, source space, or LUT intensity
- **THEN** visible LUT cards re-render with the same change

#### Scenario: Select a rendered card
- **WHEN** the user selects a LUT card
- **THEN** the main preview applies that LUT and the selected card receives a visible selection state

### Requirement: Scalable contact sheet
The contact sheet SHALL lazily create cards, cancel obsolete renders, support folder-local search, and allow preview-size adjustment.

#### Scenario: Scroll a large folder
- **WHEN** LUT cards leave the lazy grid during scrolling or the render context changes
- **THEN** obsolete preview tasks do not publish stale images
