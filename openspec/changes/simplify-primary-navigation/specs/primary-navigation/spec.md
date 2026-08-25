## ADDED Requirements

### Requirement: Three stable primary modes
The application SHALL expose exactly Viewer, LUT Manager, and LUT Editor as top-level sidebar modes, and the selected row SHALL reflect only the current top-level mode.

#### Scenario: Enter LUT Manager after browsing a folder
- **WHEN** the user browses a LUT folder and then selects LUT Manager
- **THEN** LUT Manager remains selected while the folder stays represented only as LUT scope

#### Scenario: Primary labels
- **WHEN** the application displays its primary sidebar
- **THEN** it labels the three destinations Viewer, LUT Manager, and LUT Editor

### Requirement: Viewer-owned image library
The application SHALL expose project-image List and Gallery presentations as a subordinate surface within Viewer rather than as a fourth top-level mode.

#### Scenario: Browse images
- **WHEN** the user invokes Images from Viewer
- **THEN** Viewer remains the selected primary mode and the List/Gallery image browser is shown

#### Scenario: Open a browsed image
- **WHEN** the user opens an image from List or Gallery
- **THEN** Viewer returns to its preview surface with that image selected

### Requirement: LUT-owned scope controls
All LUTs, Starred, folder scope, and LUT import SHALL be controlled within the LUT library column and SHALL NOT alter the selected primary mode.

#### Scenario: Change scope in LUT Manager
- **WHEN** the user selects Starred or a LUT folder while LUT Manager is active
- **THEN** the LUT table is filtered and LUT Manager remains selected

### Requirement: Project-free interface compatibility
The application SHALL remove project creation and switching from the interface while preserving existing image storage and providing an implicit image workspace when none exists.

#### Scenario: Existing storage
- **WHEN** the application starts with an existing current image store
- **THEN** it reuses that store without moving or deleting its images

#### Scenario: Fresh storage
- **WHEN** the application starts without an image store
- **THEN** it creates an implicit destination so Import Images is immediately usable

#### Scenario: Removed saved Images section
- **WHEN** a saved session contains the former `images` top-level value
- **THEN** the session opens safely in Viewer
