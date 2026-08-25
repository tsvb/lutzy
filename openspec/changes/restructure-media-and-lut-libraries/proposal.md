## Why

Viewer currently opens image management by replacing the entire preview workbench with a List/Gallery surface. That transition is visually disruptive, and it mixes two different jobs: choosing media to inspect and managing a media library. At the same time, physical LUT folders cannot represent cross-folder concepts such as “Low Saturation”, while LUT Manager's table is efficient for bulk work but does not let users judge looks visually.

The application needs a clearer ownership model for the same local LUT set: Workspace chooses the job, Viewer keeps its comparison workbench stable, Media Library owns media import and browsing, LUT Library owns visual discovery, and LUT Manager owns structured metadata and file work.

## What Changes

- Add **Media Library** and a provisionally named **LUT Library** beside Viewer, LUT Manager, and LUT Editor in the Workspace sidebar.
- Replace Viewer's whole-surface Images mode with a secondary column that shows media at the top and LUT sources below it.
- Keep Viewer's right side stable: comparison/preview above and the LUT gallery below.
- Let Media Library import images and videos and browse them in Finder-like List or Columns presentations.
- Organise Viewer and LUT Manager LUT sources into physical Folders, metadata-backed Collections, and the built-in Starred filter.
- Add manual Collections that can group LUTs across physical folders without moving or copying files.
- Keep LUT Manager focused on physical organisation, metadata, collections, and bulk actions.
- Put visual LUT browsing in a separate LUT Library surface rather than presenting it as a Manager table mode.
- Keep LUT Library local-only: it displays LUTs already imported into or created by the app and has no marketplace, download catalogue, or creator-network scope.
- Show a LUT preview, name, vendor or Custom origin, and no more than three tags on each LUT Library gallery card.
- Open a LUT detail from the visual Library with multiple sample images and an original-versus-graded comparison rendered through the same colour pipeline as Viewer.
- Treat supplied screenshots as non-normative references for hierarchy and interaction, not pixel-level designs to reproduce.

## Capabilities

### New Capabilities

- `workspace-library-navigation`: Defines the five provisional Workspace destinations, Viewer's secondary column, stable workbench, and workspace-state boundaries.
- `media-library`: Defines image/video import, Finder-like List/Columns browsing, and handoff of images to Viewer.
- `lut-virtual-collections`: Defines physical folders, manual metadata collections, and Starred as distinct LUT source types.
- `lut-library-visual-browser`: Defines the separation between visual LUT discovery and management, gallery card metadata, LUT details, and sample-image rendering.

### Modified Capabilities

None. The repository has no archived base specifications; this change supersedes the relevant navigation decisions in `simplify-primary-navigation` and `add-image-gallery-mode` when implemented.

## Impact

This affects primary navigation, Viewer composition, image-management ownership, media persistence, LUT scope state, LUT metadata, LUT Library presentation, LUT Manager responsibility, sample assets, and render-preview caching. Likely implementation areas include `AppSection`, `NavigationSidebar`, `ContentView`, `ImageManagerView`, `LUTFolderSidebar`, `LUTSidebar`, `LibraryManagerView`, `AppViewModel`, `ProjectStore`, `LUTTagStore`, and new collection/origin stores.

Existing image files, LUT files, folder hierarchy, tags, favourites, and colour transforms are preserved. This change does not require moving user LUTs or deleting the current project-backed image storage.
