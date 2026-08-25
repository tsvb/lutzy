# Source requirements ledger

This file preserves the user's original intent and the evolution of decisions behind this OpenSpec. It is evidence and context, not a pixel-level UI contract. Where a reference image and written request differ, the written request wins.

## Working constraints

- All supplied product screenshots are references only. They communicate hierarchy, density, or interaction ideas; implementation must adapt them to LUTzy's current macOS interface.
- Do not copy another product's visual design or infer unrequested marketplace features from a screenshot.
- Keep image/media functionality out of LUT Manager.
- Keep work on the current branch and ensure a later merge can build and run.
- Do not use Superpowers skills for this work.

## Confirmed product requirements

### Viewer and comparison

1. Viewer chooses LUTs visually from the lower gallery; 2×2, 3×3, and other comparison cells use gallery click/drag assignment instead of repeated LUT dropdown lists. Recorded in `add-direct-grid-assignment`.
2. Viewer LUT browsing is folder-first. Physical folders may be nested without an application-defined depth limit, and choosing a parent shows LUTs in all descendants. Recorded in `add-viewer-folder-contact-sheet` and `support-deep-lut-folder-tree`.
3. The Viewer control described as “browse images as a list or gallery” currently replaces the whole detail area and makes the layout feel broken. Remove that Viewer mode and its toggle.
4. Put the active media chooser on the left side of Viewer. The right side remains the current workbench: comparison/preview above and the LUT gallery below.
5. Viewer's secondary column places Media at the top. Below it, LUT sources are grouped as Folder, Collection, and Starred.
6. The Viewer media area should be named and modelled so video items can appear in the future; video playback itself has not yet been requested for this implementation phase.

### Media Library

1. Add Media Library as a first-class Workspace destination.
2. Media Library imports images and videos.
3. Media Library supports List and Finder-like Columns browsing. “Columns” means hierarchical Finder columns, not the removed image thumbnail Gallery.
4. Existing project-backed media must be preserved; Project is not a visible navigation level.

### LUT organisation

1. Folder is physical organisation and preserves recursively nested filesystem structure.
2. Collection is metadata, not a physical folder. Users select LUTs and group them under a named Collection without moving or copying files.
3. Collections cross folder boundaries. Source example: folders organised by camera brand, with low-saturation LUTs from several brands grouped into a “Low Saturation” Collection.
4. A LUT may belong to multiple Collections. Removing membership or deleting a Collection must not delete or move the LUT.
5. Starred is a separate built-in virtual group backed by favourites, not a physical folder or normal Collection.
6. The condition-builder shown in a reference is not yet a confirmed requirement. Rule-based Smart Collections remain separate future scope.

### LUT management and visual display

1. LUT Manager is explicitly for LUT management and must not contain image-management features.
2. Entering LUT Manager must not jump into a stale Viewer folder or an old nested visual-detail location. It should enter a stable All LUTs management overview.
3. A visual LUT gallery shows many LUTs with a rendered preview, name, vendor or self-made status, and at most three visible tags per card.
4. Activating a visual LUT opens a detail with several sample images so the user can inspect its effect. The accepted interaction is a draggable vertical Before/After split with sample thumbnails below it; the reference remains non-normative for styling.
5. Gallery/detail previews must share Viewer's real render and colour pipeline so the same source and LUT do not produce a different RGB result in different parts of the app.
6. LUT display/discovery and LUT management are separate top-level Workspace destinations named LUT Library and LUT Manager.
7. LUT display is strictly for the local LUT Library: LUTs already imported into or created by the app. Marketplace, creator network, remote catalogue, and download features are explicitly excluded.
8. LUT Library may Star, add a LUT to an existing Collection, and open it in Viewer. LUT Manager owns Collection creation/rename/deletion, complete membership editing, names, origin, tags, folder movement, and deletion.
9. Current LUT Manager metadata editing is inconvenient, especially tags. The add-only Tag sheet does not provide enough visibility or correction control.
10. “Edit LUT” in Manager means metadata and organisation only. Any operation that changes colour values or the LUT transform belongs exclusively to LUT Editor.
11. Use a persistent right-side Manager Inspector as the first design to test. It supports full single-selection metadata, direct Tag chips, and common/mixed multi-selection editing. The interaction may be refined after inspecting the implemented app.
12. Every LUT Library Gallery card uses the same currently selected sample image. Different sample images are available in LUT detail, not assigned as individual LUT cover images.
13. LUT Library samples are fixed built-in app assets. Users do not add or manage Library samples through Media Library; personal-image testing remains in Viewer.
14. The built-in set contains four images: skin-tone portrait, outdoor sky/foliage, indoor mixed light, and saturated objects with neutral references.
15. LUT detail uses a vertically divided Before/After image with a horizontally draggable split. Holding Space temporarily shows the complete original and release restores the comparison.
16. Gallery cards show at most three Tags. User-authored Tags take priority, then measured Tags fill remaining positions; each group uses stable alphabetical order and users do not manage a separate card-display order.

### Colour consistency

The same source image and LUT previously appeared different between `code_ground/lut-viewer` and this project. The pipeline investigation and correction are recorded in `align-color-pipeline`. Any new LUT Gallery or detail must reuse the production Viewer pipeline rather than introduce a thumbnail-only transform.

## Original request excerpts

These excerpts preserve the user's wording. Line breaks were normalised only for readability.

> viewer那邊看一下有沒有辦法這樣呈現  
> lut先用FOLDER層級來管好了  
> 所以選定folder層級 下面列的就是所有folder下的lut

> 2x2或是3x3那些  
> 參考一下這畫面的設置  
> 影片中展示的是把lut從下方拖曳進去  
> 或是點選 就可以切換  
> 目前用drop down list太不直覺了

> lut層級大概是可以這樣分層 理論上可以無限nested

> collection功能就是  
> 可以把某些lut選擇起來變成某個collection  
> 但他不是實體folder 偏向是meta data  
> 舉例來說  
> 我folder按照相機品牌分  
> 但我想把低飽和的變成一個低飽和collection

> 在viewer模式按下去那個brows image as list or gallery按下去會整個跑掉  
> 這功能感覺不需要了

> 找了一張參考圖給你但不是要你照抄  
> 我在想viewer那邊是不是可以把images放到左邊  
> 未來那邊也可以列出影片  
> 右邊就留下現在上面是對比視窗 下面是lut就好  
> 然後workspace就多一個叫做Media Library  
> 那邊可以import images跟videos  
> 然後show as column還是list  
> 有點像是finder那樣

> 最外面維持workspace  
> 第二層那邊 上面media lib  
> 下面lut  
> 分三區, folder, collection跟star  
> 右邊就原本的  
> 另外我給你圖片目前都是參考 你直接改掉就跟現狀不合吧？

> Lut manager在Gallery那邊  
> 我希望每個lut點進去可以這樣  
> 有個幾個sample image 然後可以看一下效果  
> 記住這只是參考圖

> 這同樣是參考圖 這是gallery mode  
> 顯示出了一堆lut這樣  
> 我要的可能就會是名字 哪個廠家出的 或是自製的  
> 然後有標籤的話 每個最多顯示三個標籤這樣

> 另外我有在思考 是不是可以這樣展示？  
> 但細節我還沒想好  
> 到底是要把lut展示 跟lut管理拆開 還是怎樣  
> 好像拆開比較好？

> 可以啊 Manager那邊要不要能編輯collection?  
> 另外就是manager那邊好像 lut編輯也不太方便？ 尤其是tag

> 先試試看inspector吧 沒意見

## Requirement evolution and supersession

| Earlier direction | Current direction | Status |
| --- | --- | --- |
| Exactly Viewer, LUT Manager, LUT Editor at Workspace level | Viewer, Media Library, LUT Library, LUT Manager, LUT Editor | Superseded / confirmed |
| Viewer owns an Images List/Gallery surface | Remove the whole-surface Viewer browser; put media in the secondary column | Superseded |
| LUT Manager may gain Gallery as another presentation | Separate top-level LUT Library for discovery and LUT Manager for organisation | Confirmed split |
| Collections may resemble the reference's Smart Collections | Manual metadata Collections only | Confirmed |

## Confirmed follow-up decisions

### 2026-08-26 — Local LUT Library only

The visual LUT space operates on the same local LUT set as LUT Manager. It is not a marketplace and does not include online download, creator, account, licensing, rating, or remote-catalogue features. The remaining question is only how local LUT display and local LUT management should be separated in the interface.

### 2026-08-26 — Display and management write boundary

LUT Library is allowed to Star, add to an existing Collection, and open a LUT in Viewer. LUT Manager owns Collection structure, full membership editing, LUT metadata, folder moves, and deletion. Manager replaces the current add-only Tag sheet with the confirmed persistent metadata Inspector.

### 2026-08-26 — Manager edits metadata, Editor edits transforms

LUT Manager may edit display name, Vendor/Custom/Unknown origin, tags, Collection membership, physical folder, and Starred state. It must not change LUT colour values, curves, interpolation, or transform data; those operations remain in LUT Editor.

### 2026-08-26 — Test a persistent Manager Inspector

The first Manager metadata interaction will use a persistent right-side Inspector. Single selection exposes full metadata; Tags are directly addable/removable chips; multi-selection exposes common and mixed states with explicit safe batch actions. This is the first design to validate in the running app, not a permanent pixel-level constraint.

### 2026-08-26 — Five separate Workspace destinations

Workspace contains Viewer, Media Library, LUT Library, LUT Manager, and LUT Editor. LUT Library and LUT Manager are separate top-level destinations rather than Gallery/Table modes or children of a shared LUT destination.

### 2026-08-26 — One shared Gallery sample

All LUT Library Gallery cards render the same currently selected sample image so users compare LUT effects against constant source pixels. Per-LUT cover images are excluded; additional samples are switched in LUT detail.

### 2026-08-26 — Fixed built-in samples

LUT Library uses only a fixed set of licensed sample images bundled with the app. There is no Add Sample, custom sample collection, or Media Library sample membership in this scope. Viewer remains the place to test LUTs on personal media.

### 2026-08-26 — Four representative sample scenes

The fixed set contains exactly four licensed assets: a skin-tone portrait; an outdoor sky-and-foliage scene; an indoor mixed-light scene; and a saturated-object scene with neutral references. Each asset needs a documented colour profile and source-space assumption.

### 2026-08-26 — LUT detail comparison interaction

The earlier reference with a central Before/After divider and sample thumbnails is accepted as the interaction direction. LUT detail uses a horizontally draggable vertical split; holding Space temporarily reveals the complete original. The reference still does not prescribe pixel-level styling.

### 2026-08-26 — Gallery Tag priority

Cards display at most three Tags. User-authored Tags fill the available slots first in stable alphabetical order, followed by measured Tags in stable alphabetical order. Full Tags remain visible in detail and Manager; no manual card-tag ordering feature is added.

## Reference-image index

The following files are non-normative references. Their recorded purpose is limited to the note beside each path.

| File | Recorded purpose |
| --- | --- |
| `/Users/world4jason/Desktop/Screenshot 2026-08-25 at 7.08.53 PM.png` | Folder hierarchy beside a large preview and LUT contact sheet |
| `/Users/world4jason/Desktop/Screenshot 2026-08-25 at 7.04.35 PM.png` | Visual LUT assignment to comparison cells; avoid dropdown-only selection |
| `/Users/world4jason/Desktop/Screenshot 2026-08-25 at 7.04.09 PM.png` | Recursive physical LUT folders and separate collection groups |
| `/var/folders/pt/8st82qw57rs05k145xw2_5w40000gn/T/codex-clipboard-feb7a4a0-964b-47e6-ae85-6e8b6c9e61a9.png` | Collection naming/condition-dialog reference; conditions are not in current scope |
| `/var/folders/pt/8st82qw57rs05k145xw2_5w40000gn/T/codex-clipboard-66233ea2-c36d-45b8-86de-8798b7964f7b.png` | Evidence of the disruptive Viewer Images surface |
| `/Users/world4jason/Desktop/Screenshot 2026-08-25 at 9.19.10 PM.png` | Media on the left, grading results on the right |
| `/var/folders/pt/8st82qw57rs05k145xw2_5w40000gn/T/codex-clipboard-8e4132d6-518d-4053-9163-19e18bd8d656.png` | Workspace outer column; Viewer secondary column with Media then Folder/Collection/Starred |
| `/var/folders/pt/8st82qw57rs05k145xw2_5w40000gn/T/codex-clipboard-961f7ba8-7592-449e-a858-4f212a527073.png` | LUT detail with several samples and effect comparison |
| `/var/folders/pt/8st82qw57rs05k145xw2_5w40000gn/T/codex-clipboard-5ce320a6-c95c-4cb0-90ee-5cfb870fb766.png` | Visual LUT Gallery card density and metadata hierarchy |
| `/var/folders/pt/8st82qw57rs05k145xw2_5w40000gn/T/codex-clipboard-ecbee535-4b0d-470e-9e8e-89acd85ca610.png` | Possible curated showcase layout; does not by itself request marketplace/download features |
| `/var/folders/pt/8st82qw57rs05k145xw2_5w40000gn/T/codex-clipboard-a46aaa37-7ffc-422f-ba1a-706eecefa237.png` | Consolidated evidence for Collections, Viewer browser removal, and Media Library |
| `/var/folders/pt/8st82qw57rs05k145xw2_5w40000gn/T/codex-clipboard-ba66183b-4b3f-4a56-b62d-dfde63a9a59b.png` | Consolidated final Viewer information hierarchy |
| `/var/folders/pt/8st82qw57rs05k145xw2_5w40000gn/T/codex-clipboard-d0181aac-c1d2-4658-9667-514bec8e0b36.png` | Consolidated LUT sample-detail request |
| `/var/folders/pt/8st82qw57rs05k145xw2_5w40000gn/T/codex-clipboard-5d49264b-f669-4619-a06a-638252e97e46.png` | Consolidated Gallery-card metadata request |
| `/var/folders/pt/8st82qw57rs05k145xw2_5w40000gn/T/codex-clipboard-5411ffd7-3444-4663-a8b9-ec10b4e680ac.png` | Reference for the now-resolved split between visual display and management |

## OpenSpec record map

| OpenSpec change | What it records | Relationship to this change |
| --- | --- | --- |
| `align-color-pipeline` | RGB and LUT-render consistency | Required foundation; new previews reuse it |
| `add-image-gallery-mode` | Earlier image List/Gallery manager | Superseded by Media Library List/Columns and Viewer toggle removal |
| `simplify-primary-navigation` | Removal of Project level and stable primary modes | Extended by Media Library and the visual-LUT placement decision |
| `add-viewer-folder-contact-sheet` | Folder-first Viewer and lower visual LUT sheet | Retained |
| `support-deep-lut-folder-tree` | Unlimited recursive folder presentation and descendant scope | Retained |
| `add-direct-grid-assignment` | Click/drag LUT assignment for comparison grids | Retained |
| `restructure-media-and-lut-libraries` | Current batch: Media Library, Viewer composition, Collections, Gallery/detail, and display/management split | Active draft |
