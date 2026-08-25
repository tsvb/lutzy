## ADDED Requirements

### Requirement: Local LUT scope only
LUT Library SHALL display only LUTs already imported into or created by the local application and SHALL NOT introduce a remote catalogue, marketplace, creator network, or download workflow.

#### Scenario: Browse while offline
- **WHEN** the user opens LUT Library without a network connection
- **THEN** every locally available LUT remains browseable with no missing remote sections or account prompts

#### Scenario: Inspect a reference-inspired section
- **WHEN** LUT Library groups or highlights local LUTs visually
- **THEN** the section is derived from local library metadata and does not imply that the LUT can be downloaded from a remote service

### Requirement: Separate discovery and management responsibilities
The application SHALL provide a visual LUT Library for discovery and sample-based evaluation separately from LUT Manager's table-based file, metadata, collection, and bulk-management work.

#### Scenario: Browse visual looks
- **WHEN** the user enters LUT Library
- **THEN** the primary content is a visual Gallery over the active Folder, Collection, or Starred source without destructive bulk-management controls

#### Scenario: Manage LUT records
- **WHEN** the user enters LUT Manager
- **THEN** the existing table and organisation actions are available without sample-based detail replacing the management surface

### Requirement: Lightweight LUT Library actions
LUT Library SHALL allow Star, Add to Existing Collection, and Open in Viewer, and SHALL route structural or metadata editing to LUT Manager.

#### Scenario: Curate while browsing
- **WHEN** the user stars a LUT or adds it to an existing Collection from LUT Library
- **THEN** the local metadata updates without exposing Collection deletion, folder movement, or LUT deletion in the visual surface

#### Scenario: Request full editing
- **WHEN** the user invokes an edit action for origin, tags, name, Collection structure, folder location, or deletion from LUT Library
- **THEN** the application opens the corresponding LUT in LUT Manager rather than duplicating the management form

### Requirement: Gallery card content
Each LUT Library Gallery card SHALL show a rendered sample preview, LUT name, explicit vendor name or Custom/Unknown origin, and no more than three tags.

#### Scenario: LUT has confirmed vendor and many tags
- **WHEN** a vendor LUT has more than three tags
- **THEN** its card shows the LUT name, confirmed vendor, exactly three or fewer tags, and may indicate an additional-tag count without rendering more tag chips

#### Scenario: LUT is self-made
- **WHEN** a LUT is marked Custom
- **THEN** its card labels the origin as Custom rather than inventing a vendor from its folder

#### Scenario: Origin is absent
- **WHEN** an existing LUT has no confirmed origin metadata
- **THEN** its card displays Unknown without presenting an inferred value as fact

#### Scenario: Preview is loading
- **WHEN** a card preview is not ready or an off-screen render was cancelled
- **THEN** the card keeps stable geometry and shows a loading or unavailable state

### Requirement: Shared Gallery comparison sample
Every visible LUT Library Gallery card SHALL render its LUT against the same currently selected sample image rather than using a per-LUT cover image.

#### Scenario: Compare gallery cards
- **WHEN** multiple LUT cards are visible in Gallery
- **THEN** their source pixels, source-space interpretation, base document, and intensity are identical and only the applied LUT differs

#### Scenario: Change Gallery sample
- **WHEN** the user chooses another Gallery sample
- **THEN** every visible card updates to that same sample while preserving source, search, selection, and scroll context

### Requirement: LUT detail with multiple samples
Activating a Gallery LUT SHALL open a LUT Library detail that offers multiple fixed sample images, full metadata, and an original-versus-LUT comparison for the selected sample.

#### Scenario: Open LUT detail
- **WHEN** the user activates a Gallery card
- **THEN** the detail identifies the LUT and displays the currently selected sample with a way to compare original and graded results

#### Scenario: Change sample
- **WHEN** the user selects another sample image in LUT detail
- **THEN** the detail renders the same LUT on that sample and keeps the LUT identity and metadata unchanged

#### Scenario: Inspect all tags
- **WHEN** the card omitted tags beyond its three-tag limit
- **THEN** LUT detail exposes the complete tag set

#### Scenario: Navigate back
- **WHEN** the user leaves LUT detail with Back
- **THEN** LUT Library restores the originating Gallery source, selection, and scroll context

### Requirement: Explicit origin metadata
LUT Manager SHALL let users classify a LUT origin as Vendor with a name, Custom, or Unknown, and LUT Library SHALL display that shared metadata against stable LUT identity.

#### Scenario: Mark an imported LUT as Custom
- **WHEN** the user changes an imported LUT from Unknown to Custom in LUT Manager
- **THEN** Manager, LUT Library Gallery, and LUT detail show Custom after relaunch and after a physical folder move

#### Scenario: Assign a vendor
- **WHEN** the user assigns a non-empty vendor name in LUT Manager
- **THEN** LUT Library Gallery and detail display that vendor consistently

### Requirement: Cross-surface render parity
LUT Library Gallery and detail previews SHALL use the same production render pipeline, colour management, source-space resolution, LUT intensity semantics, and LUT transform as Viewer.

#### Scenario: Compare identical render inputs
- **WHEN** Viewer and LUT Library render the same source image, edit document, source-space choice, LUT, and intensity
- **THEN** their output RGB values agree within the existing renderer's documented tolerance

#### Scenario: V-Log sample preview
- **WHEN** a sample and LUT require V-Log source handling
- **THEN** LUT Library resolves and applies the source space through the same path used by Viewer rather than a separate thumbnail transform
