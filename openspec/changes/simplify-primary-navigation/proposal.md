## Why

The primary sidebar currently mixes workspace modes, projects, image browsing, and LUT scopes in one selection. A LUT folder or starred filter can therefore steal the selected row immediately after the user chooses LUT Manager, making navigation appear to jump backwards and fragmenting the app into too many top-level places.

## What Changes

- Reduce the primary sidebar to three stable modes: Viewer, LUT Manager, and LUT Editor.
- Remove project switching and the independent Images destination from primary navigation.
- Place List/Gallery image browsing inside Viewer as a subordinate surface.
- Move All LUTs, Starred, folders, and LUT import into the LUT library column so scope cannot override the selected top-level mode.
- Preserve existing on-disk image storage and saved sessions behind the simplified UI; create an implicit image workspace only when no existing storage is available.

## Capabilities

### New Capabilities

- `primary-navigation`: Defines the three top-level modes, ownership of image and LUT scope controls, and compatibility behaviour for older saved navigation state.

### Modified Capabilities

None.

## Impact

This affects `NavigationSidebar`, `ContentView`, `LUTSidebar`, `ImageManagerView`, the view model's navigation state, project-backed compatibility storage, session decoding, focused checks, and navigation documentation. It does not delete or relocate existing user images.
