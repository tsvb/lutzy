## ADDED Requirements

### Requirement: Local LUT scope only
LUT Library SHALL display only LUTs already imported into or created by the local application and SHALL NOT introduce a remote catalogue, marketplace, creator network, or download workflow.

#### Scenario: Browse while offline
- **WHEN** the user opens LUT Library without a network connection
- **THEN** every locally available LUT remains browseable with no missing remote sections or account prompts

#### Scenario: Inspect a reference-inspired section
- **WHEN** LUT Library groups or highlights local LUTs visually
- **THEN** the section is derived from local library metadata and does not imply that the LUT can be downloaded from a remote service

### Requirement: Import only renderable 3D LUTs
Local LUT import SHALL copy and report as imported only `.cube` files that the production 3D LUT parser can render. Unsupported 1D LUTs and malformed `.cube` files SHALL be reported as failures and SHALL NOT be copied into the managed LUT folder.

#### Scenario: Mixed vendor folder
- **WHEN** the user imports a folder containing valid 3D LUTs, 1D shapers, and malformed `.cube` files
- **THEN** valid 3D LUTs are imported, unsupported files contribute to the failed count, and the next scan shows every item reported as imported

#### Scenario: Unsupported or hostile 3D size header
- **WHEN** a `.cube` declares a 3D size outside the renderer's supported 2...128 range, including a value large enough to overflow unchecked cubing
- **THEN** import reports the file as failed without copying it or terminating the process

#### Scenario: Re-import valid duplicate
- **WHEN** a valid 3D LUT has the same content fingerprint as an existing managed LUT
- **THEN** it is reported as a duplicate and does not create another physical file or record

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

#### Scenario: Choose the three visible tags
- **WHEN** a LUT has more tags than the card can display
- **THEN** user-authored tags receive priority in stable alphabetical order and measured tags fill remaining slots in stable alphabetical order

#### Scenario: More than three user-authored tags
- **WHEN** a LUT has more than three user-authored tags
- **THEN** the first three under stable alphabetical sorting appear and no per-card manual tag-order control is required

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

### Requirement: Isolated neutral Library baseline
LUT Library SHALL render every sample from its own immutable baseline with neutral develop and adjustments, the candidate LUT at 100% intensity, the sample's declared display source space, and the application's current working/output space.

#### Scenario: Enter after editing in Viewer
- **WHEN** Viewer currently has exposure adjustments, a source-space override, a selected LUT, or non-100% intensity
- **THEN** LUT Library ignores those values and renders from the neutral Library baseline

#### Scenario: Compare Library and Viewer pipeline
- **WHEN** the exact Library source and baseline document are deliberately submitted through Viewer and LUT Library rendering paths
- **THEN** output RGB agrees within the renderer's existing documented tolerance

### Requirement: Fixed built-in sample set
LUT Library SHALL use exactly four fixed, licensed sample images bundled with the application: a skin-tone portrait, an outdoor sky-and-foliage scene, an indoor mixed-light scene, and a saturated-object scene with neutral references. It SHALL NOT import, add, remove, reorder, or replace samples through Media Library.

#### Scenario: Open on a fresh installation
- **WHEN** the user opens LUT Library before importing personal media
- **THEN** all four built-in scene types are available for Gallery and LUT detail

#### Scenario: Validate sample assets
- **WHEN** the app bundles or updates the four samples
- **THEN** each asset has documented licensing, embedded or declared colour profile, source-space expectation, and stable identity

#### Scenario: Look for custom sample management
- **WHEN** the user browses LUT Library or Media Library
- **THEN** no Add Sample, Remove Sample, or Replace Sample action is offered for the LUT Library sample set

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

### Requirement: Draggable Before/After comparison
LUT detail SHALL compare the original and LUT-rendered result in one aligned large preview using a vertically divided image with a horizontally draggable split position.

#### Scenario: Drag comparison split
- **WHEN** the user drags the Before/After divider left or right
- **THEN** the visible proportion changes while both sides remain pixel-aligned to the same sample image

#### Scenario: Hold Space
- **WHEN** the user holds Space while LUT detail has focus
- **THEN** the preview temporarily shows the complete original image and restores the prior LUT comparison and split position on release

#### Scenario: Select another sample
- **WHEN** the user chooses one of the four sample thumbnails below the preview
- **THEN** both Before and After update to the new sample while the selected LUT remains unchanged

### Requirement: Workspace-owned keyboard shortcuts
Keyboard shortcuts SHALL be routed to the active Workspace and focused interaction so hidden Viewer or LUT Library state is not mutated.

#### Scenario: Hold Space in LUT detail
- **WHEN** LUT Library detail comparison has focus and receives Space down/up
- **THEN** only the detail's temporary-original state changes

#### Scenario: Use Viewer shortcuts
- **WHEN** Viewer is active and no text field or sheet owns input
- **THEN** Viewer comparison and media/LUT navigation shortcuts retain their existing behaviour

#### Scenario: Type outside Viewer or detail
- **WHEN** Media Library, LUT Manager, LUT Editor, a search field, a metadata text field, or a sheet owns input
- **THEN** Viewer and LUT-detail shortcuts do not fire and the event remains available to the active control

#### Scenario: Leave while Space is held
- **WHEN** the owning Workspace or LUT detail disappears before key-up is delivered
- **THEN** temporary-original state is cleared immediately and is not restored as stuck on a later visit

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
