## Context

The current app uses a three-column `NavigationSplitView`. The primary column contains Viewer, LUT Manager, and LUT Editor. Viewer puts a folder-only LUT browser in the secondary column and swaps its entire detail between the preview workbench and `ImageManagerView`. LUT Manager currently has one table presentation. Folder scope is shared broadly through `browsedCategory`, favourites already live in metadata, and no collection or vendor-origin model exists.

The requested screenshots demonstrate useful relationships—media beside the work area, grouped LUT sources, visual LUT cards, and a sample-based detail—but they come from other products and do not match the current app exactly. They are reference material, not normative layouts.

## Goals / Non-Goals

**Goals:**

- Give each durable job one stable Workspace destination.
- Keep Viewer spatially stable while the user changes media and LUT scope.
- Put media selection and LUT source selection together in Viewer's secondary column without mixing their data models.
- Separate physical LUT hierarchy from cross-folder metadata groupings.
- Separate visual LUT discovery from the Manager's current bulk-oriented table.
- Make existing and selected LUT metadata easy to inspect, add, remove, and batch-correct in Manager, especially tags and Collection membership.
- Make LUT previews agree with Viewer by using the same render and colour-management path.
- Preserve user files and existing metadata during migration.

**Non-Goals:**

- Reproducing the supplied reference screenshots pixel for pixel.
- Adding video playback, scrubbing, export, or video LUT rendering in this change.
- Adding rule-based or condition-builder Smart Collections.
- Nesting Collections or making them physical folders.
- Letting users add or manage custom visual-Library sample images in this change.
- Changing LUT interpolation, V-Log conversion, colour-space policy, or export rendering.
- Removing LUT Manager's table or LUT Editor's existing file-oriented list.
- Adding an online marketplace, creator accounts, downloads, ratings, or remote catalogue APIs. Product scope is explicitly limited to LUTs already local to the app; the mobile screenshot is only a local-library presentation reference.

## Information Architecture

| Workspace destination | Secondary column | Detail area |
| --- | --- | --- |
| Viewer | Media chooser at the top; LUT Folders, Collections, and Starred below | Existing comparison/preview above; existing LUT gallery below |
| Media Library | Media locations and folder hierarchy | Finder-like Grid or List browser and media actions |
| LUT Library | LUT Folders, Collections, and Starred | Visual Gallery and sample-based LUT detail |
| LUT Manager | LUT Folders, Collections, and Starred | Existing table and bulk organisation/metadata actions |
| LUT Editor | Existing LUT-oriented navigation | Existing editor |

Workspace is global navigation. Media selection, LUT source selection, and Manager detail navigation are local navigation and never replace or re-highlight a Workspace destination.

## Content Model

### Media item

A durable Media Library manifest stored in Application Support is authoritative for media identity and logical hierarchy. A media record has a stable `MediaRecordID`, display name, kind (`image` or `video`), full logical relative path, backing locator, content fingerprint, and lightweight file metadata. UI selection and saved sessions use `MediaRecordID`; `ImageCollection.Item`'s scan-time UUID is not reused.

New imports are copied into one managed Media Library root. Folder imports preserve the complete relative hierarchy rather than flattening descendants. Name collisions receive a unique backing filename while retaining the original display name; content-identical new imports are reported as duplicates and do not create another managed record. Supported videos receive records and remain browseable even though playback is deferred.

Legacy project files are not moved. Migration enumerates every `ProjectStore.projects` Images folder, not only `current`, and records each file with an internal legacy origin key composed from project UUID and normalized relative path. The Media Library presents one aggregated logical hierarchy based on relative paths without restoring Project as a navigation level. When duplicate display names collide in the same logical location, both records remain and receive a secondary legacy-source disambiguator only where needed.

Migration is idempotent: the legacy origin key finds the same manifest record on every launch. Old current-project `session.imageName` maps to a MediaRecordID only when exactly one record in that project matches; an ambiguous or missing basename leaves no active selection and never deletes a record.

### LUT record

An on-disk LUT has a durable UUID-backed `LUTRecordID` stored in a LUT catalog. The record separates identity from its current file locator and content fingerprint. Viewer documents, comparison-grid cells, Collections, origin, display-name override, typed tags, and Starred state reference `LUTRecordID`, not a path or content hash. In-memory unsaved derived LUTs retain a transient `derived://` reference until save creates or adopts a durable record.

Metadata semantics are deliberately split:

- Record-level: display-name override, Vendor/Custom/Unknown origin, user-authored tags, Starred, and Collection membership. Identical files may differ independently.
- Content-level: measured metrics and measured tags. Identical transforms may safely share objective analysis by content fingerprint.

On first migration, every scanned file receives a distinct LUTRecordID even if two files have identical contents. Existing content-hash keyed typed tags and favourite state are copied to each matching record so no user metadata is lost; later edits diverge per record. Existing measured data remains content-level.

Catalog reconciliation follows deterministic scan-batch rules:

1. An exact known locator reuses its record ID and refreshes its fingerprint/availability.
2. A successful Manager move or rename atomically updates the file locator while retaining the record ID; a catalog-update failure must report failure and avoid publishing a second identity.
3. Missing files leave unavailable records in the catalog.
4. Reconciliation groups all unmatched files and unavailable records by fingerprint before assigning identities. A reconnect is allowed only for a bucket containing exactly one unmatched file and exactly one unavailable record. Every other cardinality is ambiguous: each unmatched file receives a distinct new record and every unavailable record is retained, so enumeration order cannot choose which duplicate inherits metadata.
5. Reconnection and rescan never delete record metadata silently.

Saving an unsaved `derived://` LUT is a catalog transaction rather than a later scan side effect:

1. Saving to a new locator creates and persists a new LUTRecordID before the active document replaces its transient reference.
2. Saving over a locator already owned by the catalog adopts that existing LUTRecordID, preserves its record-level metadata, refreshes the fingerprint, and invalidates content analysis and rendered-preview caches for the old fingerprint.
3. A new locator outside configured scan roots still becomes an explicitly catalogued external record. The catalog persists the normalized locator and, when required by the platform sandbox, the security-scoped bookmark granted by the save panel; a background folder scan is not required for it to resolve after relaunch.
4. File replacement and catalog persistence use a recovery marker so interruption can be reconciled on next launch. The application must not replace a document's transient reference or report the catalog adoption complete until the durable record can be resolved. If catalog persistence fails, the written file may remain at the requested locator, but the document stays on its transient reference and exposes a retryable registration error rather than a dangling record.

### LUT source

Viewer, LUT Library, and LUT Manager each select exactly one LUT source at a time:

- `folder(path?)`: a physical folder; `nil` means All LUTs. A selected parent includes descendant folders, preserving the current recursive behaviour.
- `collection(id)`: a user-defined virtual collection.
- `starred`: a built-in virtual source derived from favourite metadata.

Viewer, LUT Library, and LUT Manager keep independent LUT-source state. A source chosen in one Workspace never silently becomes another Workspace's scope.

### LUT collection

A collection has a stable identifier, non-empty display name, creation/update metadata, and a set of LUTRecordIDs. One LUT record may belong to zero, one, or many collections. Membership is independent of path and content duplicates so moving or renaming the file does not remove it and an identical second file does not join implicitly.

### LUT origin

Origin metadata is explicit rather than inferred as fact from a folder name. It has three states:

- Vendor, with a vendor display name.
- Custom, for a LUT created or owned by the user.
- Unknown, for existing or imported LUTs without confirmed origin metadata.

Folder names may be offered as an editing suggestion, but are not authoritative origin metadata.

Manager display name is a record-level override, not a file rename. When the override is absent, UI falls back to the current filename-derived `CubeLUT.name`. Clearing the field removes the override and restores that fallback. Rescan, relaunch, and physical folder moves preserve the override without changing the `.cube` filename.

### Visual Library sample set

LUT Library ships with exactly four fixed, representative, licensed sample images: a skin-tone portrait; an outdoor scene containing sky and foliage; an indoor mixed-light scene; and a scene containing saturated objects plus neutral references. The set has one selected sample shared across Gallery and LUT detail. Sample assets declare the source-space assumptions needed for deterministic rendering. Users cannot add, remove, reorder, or replace samples from Media Library; personal-media auditioning remains a Viewer responsibility.

## Decisions

### Use durable catalogs instead of scan-time identity

Filesystem path remains a locator and content hash remains a transform fingerprint; neither is a durable user-facing record identity. The new LUT and media manifests own stable IDs and survive rescans. This prevents path changes from breaking references and prevents identical files from being forced to share descriptive metadata.

Alternative: use path everywhere. Rejected because Manager folder moves and external renames invalidate Collections, sessions, and comparison cells.

Alternative: use content hash everywhere. Rejected because two separately imported but identical files may belong to different vendors, folders, Collections, and user vocabularies.

### Aggregate every legacy media container without moving it

Media Library indexes all legacy project Images folders into one virtual hierarchy. Legacy project UUID is retained only as an internal backing-origin component and an optional collision disambiguator; it does not restore project switching or a Project navigation level. New imports use the global managed Media Library root.

Alternative: expose only `ProjectStore.current`. Rejected because hidden projects would become unreachable even though their files still exist.

Alternative: physically merge legacy directories. Rejected because migration would create unnecessary destructive/collision risk and violates the preservation requirement.

### Add Media Library and split LUT Library from LUT Manager

Media management is a durable job, not a temporary Viewer mode. Visual LUT discovery is also materially different from management: it uses large renders, samples, and explanatory detail, while Manager uses dense rows and batch actions. The architecture therefore has five Workspace destinations: Viewer, Media Library, LUT Library, LUT Manager, and LUT Editor.

LUT Library is the visual discovery surface and has its own Workspace row. It only browses LUTs already imported into or created by the app. LUT Manager remains a separate Workspace row for metadata, physical organisation, Collections, and bulk work.

Alternative: keep media management behind the current Viewer toolbar button. Rejected because it is the layout-changing interaction the redesign is intended to remove and leaves no coherent home for future video assets.

Alternative: make Table and Gallery two presentations inside LUT Manager. Rejected because a sample-based LUT detail and browse-oriented gallery are a different task, not merely another encoding of the same management rows.

### Compose Viewer instead of swapping its detail surface

Viewer's secondary column is vertically composed. A compact Media section at the top selects the active image. Below it, a LUT section is grouped into Folder, Collection, and Starred sources. Selecting either kind of local item updates the relevant Viewer content while the right-hand comparison and LUT-gallery split remains mounted.

The current Images/Back to Viewer toolbar control and `viewerSurface == .images` route are retired. List/Gallery is not a Viewer presentation setting.

### Give display modes distinct ownership and names

The display surfaces solve different tasks and must not share copy or persisted state:

- Media Library: **Grid / List**. Grid is a Finder-like thumbnail surface with natural-aspect-ratio previews and filenames; folder hierarchy stays in the secondary sidebar.
- LUT Library: **Gallery / LUT detail**.
- LUT Manager: management **Table**.
- Viewer: no whole-surface library mode.

This prevents the removed Viewer image gallery from being confused with the new visual LUT Library.

### Keep workspace navigation state isolated

Entering LUT Manager from another Workspace destination opens the Manager overview at All LUTs, rather than inheriting Viewer's folder or visual Library detail. Navigating back from a LUT detail during the same LUT Library visit restores the prior visual source, selection, and Gallery scroll position.

Alternative: preserve every nested Manager location across Workspace switches. Rejected because it creates the reported feeling that selecting LUT Manager jumps into an unrelated old location.

### Make Media Library Finder-like without copying Finder

Grid provides a dense thumbnail browser comparable to Finder's Icon View: previews fit without cropping, filenames remain visible, and selection is shared with List. List provides a sortable, information-dense view. Folder traversal remains in the Media Library sidebar in both presentations. The current backing workspace remains an implementation detail; user-facing copy says Media Library rather than Project.

Media Library accepts supported images and videos. Images can be opened in Viewer. Videos remain browseable library records, but playback and LUT processing are deliberately deferred.

### Keep Folder, Collection, and Starred semantically distinct

Folder mirrors the recursively nested filesystem and remains the only place where moving a LUT changes physical organisation. Collection stores manual membership metadata and can cross any folder boundary. Starred is a single built-in filter backed by the existing favourite flag, not a user-deletable collection.

Collections are manual in this change. The condition-builder shown in one reference would be a separate Smart Collection capability because it needs predicates, live evaluation, and explainable matching.

### Ingest a real LUT corpus without flattening it

The supplied acceptance corpus contains four materially different sources, so source folders remain the provenance boundary:

- V-Log-ready creative looks: LUTcraft and the current non-Archive V-Log Alchemy sets, grouped by producer and then target look family.
- Display-referred creative looks: G'MIC Film LUTs, retaining its film-process folders.
- Technical transforms: LUTcraft adapters and Panasonic Standard-to-V-Log conversions, kept outside creative Gallery folders.
- Camera/vendor and unclassified archives: retained by brand or source package, but not mixed into the first ready-to-preview set until their input profile is supported or confirmed.

Generated aliases and historical material are not separate visual records: LUTcraft `sd-card` short names, virtual-environment fixtures, comparison pairs, and V-Log Alchemy `Archive` are excluded when their canonical/current file is present. FreshLUTs remains an Inbox/Unclassified source because filenames and input assumptions are inconsistent; it must not silently become a confirmed vendor or camera folder.

Folder hierarchy answers “where did this LUT come from and what input family does it belong to?” Tags and Collections answer cross-folder questions such as low saturation, monochrome, portrait, or favourites. This keeps physical moves meaningful and avoids encoding subjective style in the filesystem.

Import validates each candidate through the production 3D LUT parser before copying. A `.cube` extension alone is insufficient: 1D shapers, malformed files, and 3D dimensions outside Core Image's supported 2...128 range increment the failed count and never enter the managed folder. The dimension is range-checked before cubing it, so a hostile size header cannot trigger integer overflow. Content-identical supported 3D LUTs retain the existing duplicate-by-fingerprint behaviour.

### Preserve Manager table work and add a separate visual Library path

LUT Manager remains the place for folder moves, Collection creation/rename/deletion, full membership editing, tagging, origin editing, removal, and other batch work. LUT Library consumes the same source-filtered LUT data for browsing without exposing destructive bulk controls. Its only write actions are Star, add to an existing Collection, and open in Viewer. Gallery cards prioritise the rendered look, then show the LUT name, confirmed vendor name or Custom/Unknown origin, and up to three tags. User-authored tags fill those slots first in stable alphabetical order; measured tags fill any remaining slots in their own stable alphabetical order. Extra tags remain available in detail and Manager metadata editing; the card may show a non-tag overflow count. The design does not add manual per-LUT card-tag ordering.

Manager edits descriptive metadata and organisation only: display name, Vendor/Custom/Unknown origin, tags, Collection membership, physical folder, and Starred state. Controls that change LUT colour values, curves, interpolation, or the transform itself remain exclusively in LUT Editor.

The current Manager `Tag…` action only adds one value through a sheet. It does not make existing tags directly inspectable or removable and is insufficient as the primary metadata-editing workflow.

The first implementation will test a persistent right-side metadata Inspector. A single selection exposes editable name, origin, tags, Collection membership, folder, and Starred state. Tags are visible chips with direct add/remove actions. Multiple selections expose common and mixed values plus explicit batch add/remove actions; fields without a safe batch meaning, such as display name, are disabled. This is a testable first interaction rather than a permanent visual constraint and may be refined after running-app review.

LUT Library discovery has three explicit navigation levels. Its home is a vertically scrolling set of horizontal shelves, with four segmented facets in this order: Folder, Collection & Star, Brand, and Tag. Folder is the initial facet because every imported LUT already has honest physical placement even when Brand and Collection metadata have not been curated. The existing Folder/Collection/Starred sidebar remains a source scope: it limits the records used to construct shelves rather than becoming a second competing discovery control. Folder shelves show the immediate physical children of that active scope and roll up descendants; LUTs stored directly at the scope retain a row for that folder. Collection & Star places the built-in Starred shelf beside non-empty local virtual Collections without treating Starred as a user Collection. Brand shelves use the dedicated confirmed Origin metadata namespace only, preserving Custom and Unknown instead of guessing from folder or filename; Brand is tag-like categorisation but SHALL NOT mix into ordinary descriptive Tags. Tag shelves use the union of user-authored and measured descriptive tags, exclude internal `input:*` pipeline metadata that already has a dedicated Input field, and order broader populated rows first.

Opening a shelf heading or View All replaces the home with a complete searchable Grid for that shelf. Card activation from either home or Grid opens the same LUT Library detail rather than switching to Viewer or Manager. Detail owns a persistent full-width navigation header whose leading Back action names the originating facet or shelf and also responds to Escape; Back is not buried inside the metadata Inspector. It returns to the exact originating home or Grid context, restores the originating card/control selection, and returns keyboard and assistive-technology focus rather than dropping it when the Back control disappears. This adopts the reference's catalogue rhythm without copying its styling and without adding marketplace, creator, download, or remote content concepts.

### Use shared sample images and the production render path

LUT Library Gallery uses one shared selected sample image across every visible LUT card. Per-LUT cover images are not used: keeping the source constant makes card-to-card differences attributable to the LUT rather than the photograph. LUT detail exposes the complete sample set through thumbnails below a large preview. The preview uses a vertically divided Before/After image with a horizontally draggable split position: Before is consistently on the left and After on the right, matching Viewer. Holding Space temporarily shows the complete original; releasing Space restores the LUT comparison. The reference supplies this interaction direction, not a pixel-level visual style.

LUT Library owns an immutable sample baseline instead of inheriting the mutable Viewer document. Each sample render uses neutral develop/adjustments, the selected LUT at 100% intensity, the sample's declared display source space, and the application's current working/output space. Gallery and detail may create separate requests, but they use that same baseline and never inherit Viewer exposure, adjustments, source-space override, selected LUT, or intensity.

Every LUT Library Gallery and detail preview goes through the same `EditDocument`, source-space resolution, `RenderEngine`, colour profile, and LUT transform semantics as Viewer. Cross-surface parity is tested by passing the exact Library baseline request to both surfaces; preview caching may differ, but output RGB must agree within the renderer's existing tolerance.

Alternative: pre-bake decorative thumbnails. Rejected because they would not prove the LUT's real effect and could drift from Viewer colour handling.

### Give shortcuts one active owner

Keyboard routing is Workspace- and focus-aware. Viewer comparison/navigation shortcuts operate only while Viewer is active. LUT detail owns Space down/up only while its comparison has focus. Media Library, LUT Manager, LUT Editor text inputs, search fields, and sheets do not trigger hidden Viewer or Library actions.

Temporary-original state is explicitly cleared when its owning Workspace/detail disappears, so a lost key-up cannot leave a hidden or later-restored surface showing Original.

## State and Migration

1. Add decodable Media Library and LUT Library `AppSection` cases while continuing to decode all existing section values.
2. Create the media manifest and global managed Media Library root, then idempotently index every legacy project Images folder without moving, merging, or deleting files.
3. Replace saved basename-only image selection with MediaRecordID. Migrate the old current-project basename only on an unambiguous match.
4. Retire the persisted Viewer image-presentation preference. An old `imageManager.presentation` value is ignored rather than mapped automatically; Media Library owns its independent Grid/List presentation.
5. Create one LUT catalog record per scanned file, including identical-content duplicates, then migrate typed tags and favourites from content-hash storage to each corresponding record. Keep measured metrics/tags content-level.
6. Migrate persisted path-based Viewer and comparison-cell references to LUTRecordID through exact scanned locator matching. Unresolved legacy paths remain non-destructive missing references rather than selecting another identical LUT.
7. Add Collection membership, origin, display-name override, and record-level tag/favourite metadata with tolerant decoding; existing LUTs begin with no Collections, Unknown origin, and no display-name override.
8. Keep missing LUT and media records so reconnecting or rescanning can restore them; never delete metadata silently.
9. Keep LUT Manager at All LUTs on entry and keep visual Gallery state owned by LUT Library.

## Risks / Trade-offs

- **The Viewer secondary column could become dense.** → Give Media and LUT sources clear section headers, independently scrollable or collapsible regions, and minimum useful heights.
- **Grid may be confused with LUT Gallery.** → Label the Media Library control `Grid`, keep folder navigation in its sidebar, and reserve `Gallery` for sample-based LUT discovery.
- **Video import may imply playback.** → Label unsupported Viewer actions clearly and keep playback outside acceptance criteria.
- **Vendor metadata is missing for existing LUTs.** → Use Unknown and provide explicit metadata editing; never present an inferred folder name as confirmed fact.
- **Legacy projects can contain colliding paths and basenames.** → Aggregate by stable records, keep legacy origin internally, show a secondary disambiguator only for collisions, and never guess an ambiguous saved selection.
- **External LUT moves can be ambiguous when contents are duplicated.** → Reconnect by fingerprint only for exactly one missing candidate; otherwise create a distinct record and preserve the missing one.
- **Many LUT Library previews can be expensive.** → Render lazily, cancel off-screen work, key caches by sample/render context/LUT identity, and keep card geometry stable while loading.
- **Sample previews could disagree with Viewer.** → Pin cross-surface parity tests to the same source/document/LUT inputs and avoid a separate thumbnail colour path.
- **Fixed samples may not represent every workflow.** → Start with a small varied set; custom sample management can be scoped separately after the core interaction is validated.

## Open Questions

None. Product-level decisions raised during the requested grilling session are resolved and recorded in `source-requirements.md`.

Current explicit assumptions: LUT Library is local-only; Collections are manual and flat; Media Library uses Grid/List while folder hierarchy remains in its sidebar; video playback is future work.

## Complete measured taxonomy and local similarity

The first tagger only emitted outlier traits. A colour LUT with ordinary saturation and contrast could therefore retain only its hidden `input:` machine tag and appear untagged in Gallery and Manager. The measured vocabulary now has complete, mutually exclusive baseline axes:

- colour mode: `彩色` or `黑白`;
- colour saturation: `低飽和`, `標準飽和`, or `高飽和` for non-monochrome LUTs;
- contrast: `低對比`, `標準對比`, or `高對比`.

Optional measured traits such as `暖調`, `冷調`, `分離調色`, `霧面`, `高光收斂`, and skin behaviour remain additive. The input-space tag remains available for filtering but is not a visible card chip. A tagger-version bump remeasures existing content records while preserving record-level user Tags.

Import similarity is a post-import review, not an automatic filing system. It compares the new LUT's persisted perceptual metrics with pre-existing local LUTs only when both declare the same input space and colour mode. Distance normalises contrast, saturation, endpoints, neutral chroma/hue, split angle, and skin response by perceptually useful ranges; circular hue differences are weighted down when neutral chroma is too weak for hue to be meaningful. The UI presents at most the three closest results above a documented confidence floor and explains shared measured traits. Exact fingerprints remain the import deduplicator's responsibility and never appear as recommendations.

This v1 intentionally does not use filenames, vendors, folders, typed Tags, remote catalogues, or learned embeddings. Recommendations are read-only: the user may inspect them, but import does not mutate names, Tags, Collections, Stars, or physical location from a match.

Import is one end-to-end transaction per window: copy, rescan, measurement, and review are queued in order. The filesystem writer queue is shared process-wide because every window targets the same managed Library. If a later queued batch finishes while an earlier review is still open, the review batches are combined instead of replacing unseen recommendations.
