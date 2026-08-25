## ADDED Requirements

### Requirement: Image presentation switch
The image manager SHALL provide List and Gallery presentation modes and SHALL remember the last selected mode.

#### Scenario: First use
- **WHEN** no presentation preference exists
- **THEN** the image manager opens in List mode

#### Scenario: Returning to Images
- **WHEN** the user selects Gallery and later returns to the image manager
- **THEN** Gallery remains selected

### Requirement: Shared selection
List and Gallery SHALL operate on the same selected image set.

#### Scenario: Switching presentation
- **WHEN** images are selected and the user switches between List and Gallery
- **THEN** the same images remain selected and the action count does not change

#### Scenario: Modified gallery selection
- **WHEN** the user Command-clicks or Shift-clicks gallery items
- **THEN** the selection follows macOS toggle and contiguous-range conventions

### Requirement: Gallery presentation
Gallery SHALL display project images in a responsive thumbnail grid with filename, folder context, loading state, and visible selection state.

#### Scenario: Window width changes
- **WHEN** the image manager becomes wider or narrower
- **THEN** the gallery changes its column count while maintaining usable card widths

#### Scenario: Thumbnail is pending
- **WHEN** an image thumbnail has not finished generating
- **THEN** its card displays a stable placeholder without changing card geometry

### Requirement: Action parity
Gallery SHALL provide the same Open, Export Selected, Remove, and context-menu actions as List mode.

#### Scenario: Open from gallery
- **WHEN** the user double-clicks a gallery image or selects one and invokes Open
- **THEN** that image opens in Viewer

#### Scenario: Batch action from gallery
- **WHEN** multiple gallery images are selected and Export Selected or Remove is invoked
- **THEN** the action receives exactly the shared selected set
