## ADDED Requirements

### Requirement: Five stable Workspace destinations
The application SHALL expose Viewer, Media Library, LUT Library, LUT Manager, and LUT Editor as the five top-level Workspace destinations, and local content selections SHALL NOT change the highlighted Workspace destination.

#### Scenario: Workspace labels
- **WHEN** the primary sidebar is displayed
- **THEN** it presents large icons for Viewer, Media Library, LUT Library, LUT Manager, and LUT Editor in a compact outer rail; each icon exposes its full name on hover and to assistive technology, and the active destination is visually distinct

#### Scenario: Navigate the compact Workspace rail without a pointer
- **WHEN** a keyboard or assistive-technology user moves through the Workspace destinations
- **THEN** every icon is an operable control with its full destination name and selected state

#### Scenario: Activate a destination while its hover name is visible
- **WHEN** the user single-clicks a Workspace icon after its hover label appears
- **THEN** that first click immediately activates the destination because the hover label does not receive pointer events or create a separate interaction surface

#### Scenario: Select a local source
- **WHEN** the user selects media, a LUT folder, a collection, or Starred within a Workspace destination
- **THEN** the active Workspace row remains selected

### Requirement: Viewer secondary-column composition
Viewer SHALL place a Media chooser at the top of its secondary column and SHALL place LUT sources grouped as Folders, Collections, and Starred below it.

#### Scenario: Inspect Viewer navigation
- **WHEN** Viewer is active
- **THEN** media and LUT sources are simultaneously reachable from the secondary column without opening another Viewer surface

#### Scenario: Resize Viewer navigation sections
- **WHEN** the user drags the divider between Media and LUT sources
- **THEN** the Media and LUT regions resize continuously while both retain a usable minimum height

#### Scenario: Select media
- **WHEN** the user selects an image in the Viewer Media section
- **THEN** the selected image becomes the active Viewer source while the LUT-source selection remains unchanged

#### Scenario: Select a video record
- **WHEN** the user selects an imported video in the Viewer Media section
- **THEN** the record remains visibly selectable and is labelled as Video, while the current image workbench is not replaced and the application states that playback is not available yet

#### Scenario: Select a LUT source
- **WHEN** the user selects a Folder, Collection, or Starred source
- **THEN** the lower LUT gallery updates while the active media item remains unchanged

### Requirement: Stable Viewer workbench
Viewer SHALL keep its existing comparison or preview region above its LUT gallery and SHALL NOT replace the workbench with a whole-surface image List or Gallery.

#### Scenario: Inspect the Viewer detail composition
- **WHEN** Viewer is active with one or more imported media records
- **THEN** its detail contains the comparison or preview region directly above the LUT Gallery, without an inline media thumbnail strip between them

#### Scenario: Change active media
- **WHEN** the user changes the active image from Viewer's secondary column
- **THEN** the comparison region and LUT gallery remain in their existing spatial regions and update their content in place

#### Scenario: Removed image-browser toggle
- **WHEN** Viewer is active
- **THEN** no Images or Back to Viewer control offers to replace the workbench with an image-management surface

### Requirement: Independent workspace state
Viewer LUT scope, LUT Library navigation, and LUT Manager navigation SHALL be independent, and entering LUT Manager from another Workspace destination SHALL open the Manager overview at All LUTs rather than a visual detail or Viewer's active source.

#### Scenario: Enter Manager after Viewer browsing
- **WHEN** the user selects a nested LUT folder in Viewer and then enters LUT Manager
- **THEN** LUT Manager opens its All LUTs overview and Viewer retains its own folder selection for a later return

#### Scenario: Return from LUT Library detail
- **WHEN** the user opens a LUT detail and navigates back without leaving LUT Library
- **THEN** the prior LUT Library source, selection, and Gallery scroll context are restored
