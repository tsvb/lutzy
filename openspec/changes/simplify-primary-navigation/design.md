## Context

`NavigationSidebar` currently drives one `List(selection:)` with several unrelated target types: app section, project image browser, starred LUTs, and LUT folders. The selection getter prioritises scope state over the current app section, so choosing LUT Manager can immediately move the visible selection back to a previously browsed folder. Project images are also exposed both as a top-level Images destination and as Viewer browser/filmstrip UI.

The product has three durable jobs: inspect images through LUTs, organise LUTs, and build/edit a LUT. Existing project directories contain user images and cannot be discarded merely because project switching is removed from the interface.

## Goals / Non-Goals

**Goals:**

- Keep exactly three stable primary destinations: Viewer, LUT Manager, and LUT Editor.
- Make the selected primary row depend only on the current top-level section.
- Keep List/Gallery image browsing available within Viewer.
- Keep LUT scopes and import next to the LUT list they affect.
- Preserve existing images and decode saved `images` sessions safely.
- Ensure a fresh install can import images without first creating a visible project.

**Non-Goals:**

- Deleting the existing `ProjectStore` or moving image files.
- Merging multiple historical project folders automatically.
- Redesigning LUT editing or colour processing.
- Removing the Viewer filmstrip.

## Decisions

### One primary selection type

`AppSection` contains only Viewer, LUT Manager, and LUT Editor. The primary sidebar binds directly to that enum; LUT scope can no longer replace its selection. LUT Manager retains the raw value `manager` for saved-session compatibility, while its user-facing label becomes LUT Manager. LUT Editor is named explicitly rather than the ambiguous Editor.

Alternative: keep a mixed `NavigationTarget` and adjust getter priority. Rejected because one selected row would still represent two independent concepts and remain fragile as more scopes are added.

### Viewer owns image browsing

Viewer gains a subordinate Preview/Images surface controlled from its toolbar. Images renders the existing `ImageManagerView`, including its List/Gallery preference and selection model. Opening an image returns to Preview. This preserves the earlier gallery feature without creating a fourth top-level mode.

Alternative: keep All Images in the primary sidebar but style it as secondary. Rejected because it still reads as another destination and recreates the mixed-selection problem.

### LUT column owns LUT scope

All LUTs, Starred, folders, and LUT import move into `LUTSidebar`. Scope remains persistent but is displayed as a menu inside the LUT column, so entering LUT Manager does not visually jump away from the selected mode. Retaining the last scope is useful; only its ownership changes.

Alternative: clear scope whenever LUT Manager opens. Rejected because it destroys intentional filtering and treats the symptom rather than separating mode from scope.

### Hidden compatibility workspace

The UI no longer exposes project creation, switching, rename, or delete. Existing current storage remains active. When no project exists, `AppViewModel` creates one implicit image workspace so Import Images always has a destination. No existing directory is renamed, merged, or deleted.

Saved section value `images` decodes as Viewer. New sessions persist only the three supported top-level values; the Viewer sub-surface itself need not be session-persistent because Gallery/List preference already is.

## Risks / Trade-offs

- **Older users with several projects lose the switcher UI.** → Preserve every directory and reopen the last active one; do not migrate or delete data.
- **The LUT scope menu could be less visible than sidebar rows.** → Place it immediately below LUT search with the active scope always visible.
- **Viewer toolbar could become crowded.** → Use one Preview/Images toggle and hide preview-only controls while the image library surface is active.
- **A hidden workspace sounds like a project in status text.** → Remove project terminology from image-management copy while keeping internal types for compatibility.

## Migration Plan

1. Add tolerant decoding for the removed `images` top-level value.
2. Ensure a current backing workspace exists without modifying existing stores.
3. Move scope/import controls and simplify primary navigation.
4. Route image browsing through Viewer and verify open returns to Preview.
5. Retain existing files for rollback; reverting the UI restores the project switcher without a data migration.

## Open Questions

None.
