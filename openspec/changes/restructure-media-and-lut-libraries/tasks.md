## 0. Resolved product decisions

- [x] 0.1 Confirm visual LUT browsing is local-only and excludes online download, creator, and marketplace scope
- [x] 0.2 Confirm LUT Library and LUT Manager are separate top-level Workspace destinations
- [x] 0.3 Confirm every Gallery card uses the same currently selected sample image
- [x] 0.4 Confirm the sample set is fixed built-in app content and does not accept Media Library additions
- [x] 0.5 Confirm four samples: skin-tone portrait, outdoor sky/foliage, indoor mixed light, and saturated objects/neutrals
- [x] 0.6 Confirm a draggable vertical Before/After split plus hold-Space original comparison
- [x] 0.7 Confirm card tags prioritise user-authored tags, then measured tags, with stable alphabetical ordering

## 1. Durable records and migration

- [x] 1.1 Add a persisted LUT catalog with distinct LUTRecordID, file locator, fingerprint, availability, record metadata, and content-level measured data
- [x] 1.2 Migrate one record per scanned LUT file, copy legacy typed tags/favourites to every fingerprint match, and migrate exact path-based document/grid references
- [x] 1.3 Reconcile complete fingerprint buckets per scan batch; reconnect only one-unavailable/one-unmatched buckets and keep all other duplicate cases independent of enumeration order
- [x] 1.4 Add a durable media manifest and one global managed Media Library root with stable MediaRecordID and full logical relative paths
- [x] 1.5 Idempotently aggregate every legacy project Images folder without moving files and migrate unambiguous basename sessions to MediaRecordID
- [x] 1.6 Make derived-LUT save create or adopt a durable record transactionally, preserve metadata on known-locator overwrite, register outside-root locators/bookmarks, and recover or report persistence failures without publishing a dangling reference

## 2. Navigation and state boundaries

- [x] 2.1 Add Media Library and LUT Library to `AppSection` and keep tolerant decoding for all existing saved section values
- [x] 2.2 Give Viewer, Media Library, LUT Library, LUT Manager, and LUT Editor independent local navigation state
- [x] 2.3 Make LUT Manager enter at All LUTs and restore Gallery context only inside LUT Library
- [x] 2.4 Route Viewer and LUT-detail shortcuts by Workspace/focus and clear temporary-original state when its owner disappears
- [x] 2.5 Present Workspace as a compact large-icon rail with hover names, selected state, and keyboard/assistive-technology labels

## 3. Media Library

- [x] 3.1 Support mixed image/video copy import with complete nested hierarchy, durable records, duplicate detection, unique backing names, and partial-failure reporting
- [x] 3.2 Build shared-selection Finder-like Grid and List presentations over the media manifest
- [x] 3.3 Show colliding legacy names without hiding records and use legacy-source detail only as a disambiguator
- [x] 3.4 Open supported images in Viewer by MediaRecordID while keeping videos browseable without promising playback

## 4. Viewer composition

- [x] 4.1 Replace the Viewer folder-only secondary column with Media above LUT source groups
- [x] 4.2 Add Folders, Collections, and Starred source sections without listing individual LUTs in the folder tree
- [x] 4.3 Remove the Viewer Images/Back toggle, `viewerSurface == .images` route, and obsolete List/Gallery preference
- [x] 4.4 Keep the existing comparison region and LUT gallery mounted while media or LUT source changes

## 5. LUT sources and Collections

- [x] 5.1 Add independent Folder/Collection/Starred source state and descendant-inclusive filtering for Viewer, LUT Library, and LUT Manager
- [x] 5.2 Add tolerant persistence for manual Collection definitions keyed by LUTRecordID
- [x] 5.3 Add Manager create, rename, delete, add-member, and remove-member workflows with no filesystem side effects
- [x] 5.4 Preserve many-to-many membership across moves, renames, rescans, relaunches, temporary unavailability, and identical-content records
- [x] 5.5 Keep Starred record-level and separate from user Collections

## 6. LUT Manager metadata

- [x] 6.1 Add record-level display-name override, Vendor/Custom/Unknown origin, typed tags, and Starred persistence
- [x] 6.2 Keep LUT Manager's table focused on organisation and expose Gallery only through LUT Library
- [x] 6.3 Build a persistent right-side Manager Inspector for single and multi-selection metadata editing
- [x] 6.4 Replace the add-only Tag sheet with visible tag chips, direct add/remove, and common/mixed multi-selection states
- [x] 6.5 Keep Manager mutations metadata-only, leave filenames unchanged for display-name edits, and route transform-changing actions to LUT Editor

## 7. LUT Library and sample detail

- [x] 7.1 Add the four fixed licensed scene samples with stable identity and explicit colour/source-space metadata
- [x] 7.2 Build source-filtered lazy Gallery cards over one shared sample, with effective name, origin, prioritised three-tag limit, and loading state
- [x] 7.3 Render Gallery/detail from an isolated neutral 100%-intensity Library baseline through the production RenderEngine
- [x] 7.4 Build LUT detail with sample thumbnails, a draggable vertical Before/After split, hold-Space original, and complete metadata
- [x] 7.5 Restore LUT Library source, selection, sample, and Gallery scroll context on Back
- [x] 7.6 Keep Before on the left and After on the right across Viewer and LUT Library comparisons
- [x] 7.7 Add ordered Folder/Collection & Star/Brand/Tag discovery facets over the active local LUT source, keeping Brand separate from descriptive Tags
- [x] 7.8 Build a vertically scrolling discovery home of horizontal LUT shelves with accessible View All actions
- [x] 7.9 Add complete shelf Grid navigation and restore the originating home/Grid when leaving LUT detail
- [x] 7.10 Restore originating shelf/card selection plus keyboard and assistive-technology focus across Back navigation, with safe fallback when Starred removal destroys that origin
- [x] 7.11 Move LUT detail Back into a persistent full-width navigation header with contextual destination and Escape support
- [x] 7.12 Keep the discovery header top-aligned and fill the remaining surface when a grouping has no shelves

## 8. Verification

- [x] 8.1 Add migration tests for duplicate-content LUTs, move/rename/relaunch, one-missing/two-unmatched scan buckets, unavailable reconnect, legacy typed tags/favourites, and path-based session/grid references
- [x] 8.2 Add media tests for two legacy projects with colliding names/subfolders, idempotent migration, nested mixed imports, videos, duplicates, and relaunch identity
- [x] 8.3 Add focused tests for Workspace/source isolation, Collection safety, display-name fallback, Inspector mixed state, tag priority, and keyboard ownership/cleanup
- [x] 8.4 Add pixel/RGB parity checks between Viewer and LUT Library using the exact neutral Library request for display-space and V-Log LUTs
- [x] 8.5 Verify lazy rendering cancellation, stable placeholders, VoiceOver labels, narrow-window behaviour, and no hidden shortcut mutations
- [x] 8.6 Run debug/release builds, `lutcheck`, strict OpenSpec validation, running-app interface inspection, and fresh sub-agent review
- [x] 8.7 Add derived-save tests for new locators, known-locator overwrite with metadata retention/cache invalidation, outside-root relaunch resolution, and catalog-persistence failure without a dangling document reference
- [x] 8.8 Audit the supplied real LUT corpus, reject unsupported `.cube` imports before copying, and validate the running Gallery and Manager with a curated 400+ LUT hierarchy
- [x] 8.9 Add complete visible measured-tag buckets, versioned remeasurement, and preservation checks for user-authored Tags
- [x] 8.10 Add same-input-space post-import similarity review with confidence floor, explanations, exact-duplicate exclusion, and no metadata side effects
- [x] 8.11 Serialize process-wide Library writes and each window's complete import-to-review pipeline, with concurrent same-name coverage
- [x] 8.12 Coalesce duplicate card renders in a bounded preview cache and cancel hidden-level render interest
