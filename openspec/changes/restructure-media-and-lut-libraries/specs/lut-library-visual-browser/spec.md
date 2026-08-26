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

### Requirement: Three-level local discovery navigation
LUT Library SHALL provide a local discovery home made of multiple horizontally scrollable shelves, a complete Grid for one selected shelf, and a LUT detail as three distinct navigation levels.

#### Scenario: Browse the discovery home
- **WHEN** the user enters LUT Library without an open shelf or LUT detail
- **THEN** the surface shows Folder, Collection & Star, Brand, and Tag facets in that order above multiple vertically stacked horizontal LUT shelves, with Folder active initially

#### Scenario: Scope discovery from the source sidebar
- **WHEN** the user chooses a Folder, Collection, or Starred source in the existing secondary sidebar
- **THEN** every discovery shelf and count is derived only from LUTs inside that source without replacing or duplicating the sidebar

#### Scenario: Group by Brand
- **WHEN** Brand grouping is active
- **THEN** LUTs are grouped by the dedicated confirmed Origin metadata namespace, Custom remains explicit, absent origin is shown as Unknown rather than inferred from a filename or folder, and Brand values do not enter ordinary descriptive Tag shelves

#### Scenario: Group by Folder
- **WHEN** Folder grouping is active at All LUTs or a selected Folder source
- **THEN** shelves represent the next physical folder level inside that source, include descendant LUTs, and retain a row for LUTs stored directly at the selected level

#### Scenario: Group by Tag
- **WHEN** Tag grouping is active
- **THEN** each non-empty user-authored or measured Tag becomes a shelf containing the scoped LUTs carrying that Tag, except internal `input:*` pipeline metadata which remains represented by the dedicated Input field

#### Scenario: Group by Collection and Star
- **WHEN** Collection & Star grouping is active
- **THEN** Starred appears as a separate built-in shelf when non-empty and each non-empty local virtual Collection becomes another shelf containing its scoped members, with no marketplace or remote grouping

#### Scenario: Open a complete shelf
- **WHEN** the user activates a shelf heading or View All action
- **THEN** LUT Library replaces the discovery home with a complete searchable Grid for that shelf

#### Scenario: Open LUT detail from either browsing level
- **WHEN** the user activates a LUT card from a discovery shelf or its complete Grid
- **THEN** LUT Library opens the same sample-based LUT detail and Back restores the exact originating home or Grid level

#### Scenario: Originating card leaves the active source
- **WHEN** the user removes the current LUT from Starred while its card or detail is focused and that mutation removes the card or whole shelf
- **THEN** selection clears safely and Back or the mutation itself moves keyboard and assistive-technology focus to the surviving shelf control, Grid Back control, or grouping control instead of targeting a destroyed element

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

#### Scenario: Reuse a preview across discovery rows
- **WHEN** one LUT is visible in more than one Tag or Collection shelf for the same sample and render context
- **THEN** the card instances share one identity-keyed preview request or completed result instead of submitting duplicate renders

#### Scenario: Cover one navigation level with another
- **WHEN** a complete Grid or LUT detail covers an already-mounted discovery level
- **THEN** hidden card tasks release their image state and cancel their interest in unfinished renders while the visible level remains responsive

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
- **THEN** LUT Library restores the originating discovery home or complete Grid, active grouping/source, card selection, scroll context, and keyboard/assistive-technology focus target

#### Scenario: Find the previous-page action
- **WHEN** LUT detail is open
- **THEN** a persistent full-width navigation header exposes a leading Back action named for the originating facet or shelf, and pressing Escape invokes that same action without requiring the metadata Inspector

### Requirement: Draggable Before/After comparison
LUT detail SHALL compare the original and LUT-rendered result in one aligned large preview using a vertically divided image with a horizontally draggable split position. Before SHALL remain on the left and After SHALL remain on the right, matching Viewer comparison orientation.

#### Scenario: Read comparison direction
- **WHEN** LUT detail shows both sides of the selected sample
- **THEN** the original Before image and label appear on the left and the LUT-rendered After image and label appear on the right

#### Scenario: Drag comparison split
- **WHEN** the user drags the Before/After divider left or right
- **THEN** the visible proportion changes while both sides remain pixel-aligned to the same sample image

#### Scenario: Adjust comparison without a pointer
- **WHEN** the focused divider receives Left or Right or an assistive-technology increment or decrement action
- **THEN** the split moves in bounded steps and announces the visible Before and After proportions

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

### Requirement: Complete visible measured tags
Every renderable LUT SHALL receive a visible measured colour-mode tag and contrast-class tag, and every non-monochrome LUT SHALL also receive exactly one measured saturation-class tag. Remeasurement SHALL preserve all user-authored Tags.

#### Scenario: Measure a middle-range colour LUT
- **WHEN** a colour LUT falls between the low and high saturation and contrast thresholds
- **THEN** it receives `彩色`, `標準飽和`, and `標準對比` rather than appearing untagged

#### Scenario: Measure a monochrome LUT
- **WHEN** a LUT's RGB channel spread meets the monochrome threshold
- **THEN** it receives `黑白` and exactly one contrast-class tag without a misleading saturation-class tag

#### Scenario: Remeasure an existing library
- **WHEN** the complete taxonomy replaces an older measured-tag version
- **THEN** every existing LUT is remeasured and its user-authored Tags remain unchanged

### Requirement: Local post-import similarity review
After importing one or more new LUTs, the application SHALL offer a local review that lists up to three sufficiently similar pre-existing LUTs per imported LUT using measured transform behaviour rather than names or locations.

#### Scenario: Find a strong same-space match
- **WHEN** a newly imported LUT has a pre-existing LUT with sufficiently close perceptual metrics, the same declared input space, and the same colour mode
- **THEN** the review identifies that LUT, shows a bounded similarity score, and explains shared measured traits

#### Scenario: Do not force a weak match
- **WHEN** no pre-existing same-space LUT meets the confidence floor
- **THEN** the review states that no clear similar LUT was found instead of presenting an arbitrary nearest neighbour as a recommendation

#### Scenario: Keep V-Log and Display separate
- **WHEN** a V-Log LUT resembles a Display LUT numerically under their different probe references
- **THEN** the Display LUT is excluded from that V-Log LUT's recommendations

#### Scenario: Import an exact duplicate
- **WHEN** import detects an identical content fingerprint
- **THEN** the file remains in the duplicate count and does not appear as a similarity recommendation

#### Scenario: Review without metadata mutation
- **WHEN** similarity recommendations are generated or dismissed
- **THEN** LUT filenames, physical folders, origin, user Tags, Collections, and Starred state remain unchanged

#### Scenario: Import two batches back to back
- **WHEN** two file or folder imports are submitted before the first batch has finished scanning and measuring
- **THEN** the application serializes each complete import pipeline, preserves distinct same-name LUTs under unique managed filenames, reports truthful tallies, and retains both batches of recommendations until the user dismisses or inspects them
