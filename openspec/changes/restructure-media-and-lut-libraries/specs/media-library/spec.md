## ADDED Requirements

### Requirement: Media Library import
Media Library SHALL import supported image and video files and SHALL identify each imported item by media kind without requiring a visible Project workflow.

#### Scenario: Import mixed media
- **WHEN** the user imports a supported folder containing images and videos
- **THEN** Media Library records every supported item, preserves its folder context, and labels its media kind

#### Scenario: Unsupported file
- **WHEN** an imported selection contains an unsupported file
- **THEN** the file is skipped or reported without preventing supported items from being imported

### Requirement: List and Columns presentations
Media Library SHALL provide List and Finder-like Columns presentations over the same media set and selection, where Columns traverses folder hierarchy one level per column rather than displaying a thumbnail grid.

#### Scenario: Switch presentation
- **WHEN** the user switches between List and Columns
- **THEN** the same media location and selected item remain active

#### Scenario: Traverse columns
- **WHEN** the user selects a folder in Columns
- **THEN** its child folders and media appear in the next column while ancestor columns remain visible

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
The application SHALL surface existing project-backed images through Media Library without moving, merging, or deleting their files.

#### Scenario: Upgrade existing storage
- **WHEN** the application opens storage created before Media Library existed
- **THEN** the existing images appear in Media Library and remain at their prior backing locations
