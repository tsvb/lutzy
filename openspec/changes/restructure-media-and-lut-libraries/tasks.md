## 0. Product decision gate

- [x] 0.1 Confirm visual LUT browsing is local-only and excludes online download, creator, and marketplace scope
- [x] 0.2 Confirm LUT Library and LUT Manager are separate top-level Workspace destinations

## 1. Navigation and state boundaries

- [ ] 1.1 Add Media Library and LUT Library to `AppSection` and keep tolerant decoding for all existing saved section values
- [ ] 1.2 Give Viewer, Media Library, visual LUT browsing, LUT Manager, and LUT Editor independent local navigation state
- [ ] 1.3 Make LUT Manager enter at All LUTs and restore Gallery context only inside the visual LUT surface

## 2. Media model and Media Library

- [ ] 2.1 Introduce stable image/video media records over the existing project-backed storage
- [ ] 2.2 Support mixed image/video import with folder context and partial-failure reporting
- [ ] 2.3 Build shared-selection List and Finder-like Columns presentations
- [ ] 2.4 Open supported images in Viewer while keeping videos browseable without promising playback

## 3. Viewer composition

- [ ] 3.1 Replace the Viewer folder-only secondary column with Media above LUT source groups
- [ ] 3.2 Add Folders, Collections, and Starred source sections without listing individual LUTs in the folder tree
- [ ] 3.3 Remove the Viewer Images/Back toggle, `viewerSurface == .images` route, and obsolete List/Gallery preference
- [ ] 3.4 Keep the existing comparison region and LUT gallery mounted while media or LUT source changes

## 4. LUT collections

- [ ] 4.1 Add tolerant persistence for manual Collection definitions and stable LUT membership
- [ ] 4.2 Add Manager create, rename, delete, add-member, and remove-member workflows with no filesystem side effects
- [ ] 4.3 Preserve many-to-many membership across LUT moves, renames, rescans, and temporary unavailability
- [ ] 4.4 Keep Starred backed by favourite metadata and separate from user Collections

## 5. LUT origin and visual Library

- [ ] 5.1 Add Vendor, Custom, and Unknown origin metadata with stable persistence and editing
- [ ] 5.2 Keep LUT Manager's table focused on organisation and expose Gallery through the confirmed separate visual-LUT destination
- [ ] 5.3 Build lazy Gallery cards with preview, name, origin, a maximum of three tags, and loading state
- [ ] 5.4 Build a persistent right-side Manager Inspector for single and multi-selection metadata editing
- [ ] 5.5 Replace the add-only Tag sheet with visible tag chips, direct add/remove, and common/mixed multi-selection states
- [ ] 5.6 Keep Manager mutations metadata-only and route every transform-changing action to LUT Editor

## 6. LUT detail and samples

- [ ] 6.1 Add a small licensed sample-image set with explicit colour/source-space metadata
- [ ] 6.2 Build visual Library LUT detail with sample selection, complete metadata, and original-versus-LUT comparison
- [ ] 6.3 Reuse `EditDocument`, `RenderEngine`, source-space resolution, and render-context cache keys from Viewer
- [ ] 6.4 Restore visual Library Gallery scope, selection, and scroll context on Back

## 7. Migration and verification

- [ ] 7.1 Verify existing media, folder hierarchy, tags, favourites, and LUT files are not moved or deleted
- [ ] 7.2 Add focused tests for navigation isolation, media presentation parity, collection safety, origin persistence, and Gallery card limits
- [ ] 7.3 Add pixel/RGB parity checks between Viewer and LUT Library for display-space and V-Log preview inputs
- [ ] 7.4 Verify lazy rendering cancellation, stable placeholders, keyboard navigation, VoiceOver labels, and narrow-window behaviour
- [ ] 7.5 Run debug/release builds, `lutcheck`, strict OpenSpec validation, and running-app interface inspection
