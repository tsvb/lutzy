## ADDED Requirements

### Requirement: Media Library import
Media Library SHALL copy supported image and video files into one global managed Media Library root, persist each item in a durable manifest, and identify it by stable MediaRecordID and media kind without requiring a visible Project workflow.

#### Scenario: Import mixed media
- **WHEN** the user imports a supported folder containing images and videos
- **THEN** Media Library records every supported item, preserves the complete nested relative hierarchy, and labels its media kind

#### Scenario: Unsupported file
- **WHEN** an imported selection contains an unsupported file
- **THEN** the file is skipped or reported without preventing supported items from being imported

#### Scenario: Import content duplicate
- **WHEN** an imported file has the same content fingerprint as an existing managed media record
- **THEN** it is reported as a duplicate and no second managed record is created

#### Scenario: Import name collision
- **WHEN** a different imported file collides with an existing backing filename in the same managed folder
- **THEN** it receives a unique backing filename while preserving its original display name and logical location

### Requirement: Durable media manifest
The Media Library manifest SHALL persist MediaRecordID, kind, display name, full logical relative path, backing locator, content fingerprint, and lightweight metadata across relaunches.

#### Scenario: Relaunch after import
- **WHEN** the app relaunches after importing nested image and video folders
- **THEN** every record keeps the same ID, kind, logical hierarchy, and backing file

#### Scenario: Scan-time item identity
- **WHEN** a presentation model or thumbnail scan rebuilds its rows
- **THEN** it uses MediaRecordID and does not expose a newly generated ephemeral UUID as durable identity

### Requirement: Grid and List presentations
Media Library SHALL provide Grid and List presentations over the same media set, folder scope, and selection. Grid SHALL use Finder-like thumbnail browsing while folder traversal remains in the Media Library sidebar.

#### Scenario: Switch presentation
- **WHEN** the user switches between Grid and List
- **THEN** the same media location and selected item remain active

#### Scenario: Browse media in Grid
- **WHEN** the user selects Grid
- **THEN** available media appears in a responsive thumbnail grid with uncropped natural-aspect-ratio previews and visible filenames

#### Scenario: Change Grid folder scope
- **WHEN** the user selects a folder in the Media Library sidebar while Grid is active
- **THEN** the grid shows media in that folder scope without adding a second hierarchical browser inside the content surface

#### Scenario: List media
- **WHEN** the user selects List
- **THEN** media appears in a sortable information-dense list with name, kind, and containing location

### Requirement: Image handoff to Viewer
Media Library SHALL let the user open a supported image in Viewer without changing or deleting the Media Library record.

#### Scenario: Open image
- **WHEN** the user activates Open in Viewer for an image
- **THEN** Viewer becomes active and displays that image as its current media source

#### Scenario: Activate a video
- **WHEN** the user selects an imported video in this change
- **THEN** Media Library keeps it browseable and does not claim that Viewer playback or LUT rendering is available

### Requirement: Existing media preservation
The application SHALL aggregate images from every existing project-backed Images folder through Media Library without moving, merging, or deleting their files and without restoring Project as a navigation level.

#### Scenario: Upgrade existing storage
- **WHEN** the application opens storage created before Media Library existed
- **THEN** images from every legacy project appear in one logical Media Library hierarchy and remain at their prior backing locations

#### Scenario: Migrate two projects with colliding names
- **WHEN** two legacy projects contain media with the same basename or logical relative path
- **THEN** both receive distinct MediaRecordIDs, remain reachable, and show a secondary legacy-source disambiguator only where the visible names collide

#### Scenario: Repeat legacy migration
- **WHEN** migration runs again for the same project UUID and normalized relative path
- **THEN** the existing manifest record is reused and no duplicate record is created

### Requirement: Saved media selection migration
New sessions SHALL persist MediaRecordID, and a legacy current-project basename SHALL migrate only when exactly one record in that project matches.

#### Scenario: Unique legacy basename
- **WHEN** the old current project contains exactly one record matching the saved imageName
- **THEN** the session adopts that MediaRecordID

#### Scenario: Ambiguous legacy basename
- **WHEN** multiple records in the old current project match the saved imageName
- **THEN** no media is auto-selected and no record is changed or removed
