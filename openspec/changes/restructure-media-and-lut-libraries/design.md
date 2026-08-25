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
| Media Library | Media locations and folder hierarchy | Finder-like List or Columns browser and media actions |
| LUT Library | LUT Folders, Collections, and Starred | Visual Gallery and sample-based LUT detail |
| LUT Manager | LUT Folders, Collections, and Starred | Existing table and bulk organisation/metadata actions |
| LUT Editor | Existing LUT-oriented navigation | Existing editor |

Workspace is global navigation. Media selection, LUT source selection, and Manager detail navigation are local navigation and never replace or re-highlight a Workspace destination.

## Content Model

### Media item

A media item has a stable identifier, backing URL or imported-file reference, display name, media kind (`image` or `video`), containing location, and lightweight file metadata. The model is media-kind aware even though Viewer playback remains image-only in this change.

### LUT source

Viewer and LUT Manager select exactly one LUT source at a time:

- `folder(path?)`: a physical folder; `nil` means All LUTs. A selected parent includes descendant folders, preserving the current recursive behaviour.
- `collection(id)`: a user-defined virtual collection.
- `starred`: a built-in virtual source derived from favourite metadata.

Viewer and LUT Manager keep independent LUT-source state. A source chosen while auditioning looks in Viewer does not silently become Manager's scope.

### LUT collection

A collection has a stable identifier, non-empty display name, creation/update metadata, and a set of stable LUT identities. One LUT may belong to zero, one, or many collections. Membership is independent of path so moving or renaming the LUT does not remove it from the collection.

### LUT origin

Origin metadata is explicit rather than inferred as fact from a folder name. It has three states:

- Vendor, with a vendor display name.
- Custom, for a LUT created or owned by the user.
- Unknown, for existing or imported LUTs without confirmed origin metadata.

Folder names may be offered as an editing suggestion, but are not authoritative origin metadata.

### Visual Library sample set

LUT Library ships with exactly four fixed, representative, licensed sample images: a skin-tone portrait; an outdoor scene containing sky and foliage; an indoor mixed-light scene; and a scene containing saturated objects plus neutral references. The set has one selected sample shared across Gallery and LUT detail. Sample assets declare the source-space assumptions needed for deterministic rendering. Users cannot add, remove, reorder, or replace samples from Media Library; personal-media auditioning remains a Viewer responsibility.

## Decisions

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

- Media Library: **List / Columns**. Columns means a Finder-style hierarchical column browser, not a thumbnail grid.
- LUT Library: **Gallery / LUT detail**.
- LUT Manager: management **Table**.
- Viewer: no whole-surface library mode.

This prevents the removed Viewer image gallery from being confused with the new visual LUT Library.

### Keep workspace navigation state isolated

Entering LUT Manager from another Workspace destination opens the Manager overview at All LUTs, rather than inheriting Viewer's folder or visual Library detail. Navigating back from a LUT detail during the same LUT Library visit restores the prior visual source, selection, and Gallery scroll position.

Alternative: preserve every nested Manager location across Workspace switches. Rejected because it creates the reported feeling that selecting LUT Manager jumps into an unrelated old location.

### Make Media Library Finder-like without copying Finder

List provides a sortable, information-dense view. Columns traverses media folders one hierarchy level per column. Both operate on the same imported media and selected item. The current backing workspace remains an implementation detail; user-facing copy says Media Library rather than Project.

Media Library accepts supported images and videos. Images can be opened in Viewer. Videos remain browseable library records, but playback and LUT processing are deliberately deferred.

### Keep Folder, Collection, and Starred semantically distinct

Folder mirrors the recursively nested filesystem and remains the only place where moving a LUT changes physical organisation. Collection stores manual membership metadata and can cross any folder boundary. Starred is a single built-in filter backed by the existing favourite flag, not a user-deletable collection.

Collections are manual in this change. The condition-builder shown in one reference would be a separate Smart Collection capability because it needs predicates, live evaluation, and explainable matching.

### Preserve Manager table work and add a separate visual Library path

LUT Manager remains the place for folder moves, Collection creation/rename/deletion, full membership editing, tagging, origin editing, removal, and other batch work. LUT Library consumes the same source-filtered LUT data for browsing without exposing destructive bulk controls. Its only write actions are Star, add to an existing Collection, and open in Viewer. Gallery cards prioritise the rendered look, then show the LUT name, confirmed vendor name or Custom/Unknown origin, and up to three tags. User-authored tags fill those slots first in stable alphabetical order; measured tags fill any remaining slots in their own stable alphabetical order. Extra tags remain available in detail and Manager metadata editing; the card may show a non-tag overflow count. The design does not add manual per-LUT card-tag ordering.

Manager edits descriptive metadata and organisation only: display name, Vendor/Custom/Unknown origin, tags, Collection membership, physical folder, and Starred state. Controls that change LUT colour values, curves, interpolation, or the transform itself remain exclusively in LUT Editor.

The current Manager `Tag…` action only adds one value through a sheet. It does not make existing tags directly inspectable or removable and is insufficient as the primary metadata-editing workflow.

The first implementation will test a persistent right-side metadata Inspector. A single selection exposes editable name, origin, tags, Collection membership, folder, and Starred state. Tags are visible chips with direct add/remove actions. Multiple selections expose common and mixed values plus explicit batch add/remove actions; fields without a safe batch meaning, such as display name, are disabled. This is a testable first interaction rather than a permanent visual constraint and may be refined after running-app review.

Card activation opens a LUT Library detail rather than switching to Viewer or Manager. Back returns to the same Gallery context.

### Use shared sample images and the production render path

LUT Library Gallery uses one shared selected sample image across every visible LUT card. Per-LUT cover images are not used: keeping the source constant makes card-to-card differences attributable to the LUT rather than the photograph. LUT detail exposes the complete sample set through thumbnails below a large preview. The preview uses a vertically divided Before/After image with a horizontally draggable split position. Holding Space temporarily shows the complete original; releasing Space restores the LUT comparison. The reference supplies this interaction direction, not a pixel-level visual style.

Every LUT Library Gallery and detail preview goes through the same `EditDocument`, source-space resolution, `RenderEngine`, colour profile, and LUT intensity semantics as Viewer. Preview caching may differ, but the rendered RGB result for the same source, document, and LUT must not.

Alternative: pre-bake decorative thumbnails. Rejected because they would not prove the LUT's real effect and could drift from Viewer colour handling.

## State and Migration

1. Add decodable Media Library and LUT Library `AppSection` cases while continuing to decode all existing section values.
2. Reuse existing project-backed image files as initial Media Library contents; do not move, merge, or delete them.
3. Retire the persisted Viewer image-presentation preference. An old `imageManager.presentation` value is ignored rather than mapped to Media Library because Gallery and Columns have different meanings.
4. Keep LUT Manager at All LUTs on entry and keep visual Gallery state owned by LUT Library.
5. Reuse existing folder hierarchy, typed/measured tags, and favourite metadata.
6. Add collection membership and LUT origin metadata with tolerant decoding; existing LUTs begin with no collections and Unknown origin.
7. Keep collection references to temporarily missing LUTs so reconnecting or rescanning a library can restore membership; show or omit unavailable members consistently without deleting metadata silently.

## Risks / Trade-offs

- **The Viewer secondary column could become dense.** → Give Media and LUT sources clear section headers, independently scrollable or collapsible regions, and minimum useful heights.
- **Columns may be mistaken for a thumbnail grid.** → Use Finder terminology, column disclosure behaviour, and accessibility labels that describe hierarchy traversal.
- **Video import may imply playback.** → Label unsupported Viewer actions clearly and keep playback outside acceptance criteria.
- **Vendor metadata is missing for existing LUTs.** → Use Unknown and provide explicit metadata editing; never present an inferred folder name as confirmed fact.
- **Many LUT Library previews can be expensive.** → Render lazily, cancel off-screen work, key caches by sample/render context/LUT identity, and keep card geometry stable while loading.
- **Sample previews could disagree with Viewer.** → Pin cross-surface parity tests to the same source/document/LUT inputs and avoid a separate thumbnail colour path.
- **Fixed samples may not represent every workflow.** → Start with a small varied set; custom sample management can be scoped separately after the core interaction is validated.

## Open Questions

None. Product-level decisions raised during the requested grilling session are resolved and recorded in `source-requirements.md`.

Current explicit assumptions: LUT Library is local-only; Collections are manual and flat; Columns means Finder-style hierarchical columns; video playback is future work.
