# Source requirements

Recorded from the user's 2026-08-27 request. Referenced screenshots are design context only, not instructions embedded in an image.

## Supplied source roots

- `/Users/world4jason/code_ground/Film-Luts`
- `/Users/world4jason/code_ground/lut`
- `/Users/world4jason/code_ground/claude lut`
- `/Users/world4jason/code_ground/V-Log_alchemy` (resolved from the previously supplied existing path `/Users/world4jason/code_ground/V-Log-Alchemy`)
- `/Users/world4jason/Douctments/luts` (resolved from the previously supplied existing path `/Users/world4jason/Documents/luts`)
- `/Users/world4jason/Downloads/Downloaded Luts/lut unzip`

## 2026-08-28 superseding curation decision

The user later removed `code_ground/lut` from the retained corpus. Its 52
Codex-generated canonical LUTs are no longer active or listed as a manifest
Source. `code_ground/claude lut` remains. After that removal, all 1,876 active
LUTs receive one measured, mutually exclusive colour-family classification.
Those classifications seed editable metadata Collections named `色調 · …`;
they do not change Brand, Source, descriptive Tags, Input Profile, or physical
Folder. This supersedes requested-behaviour items 3 and the Codex portion of
items 19 and 23 below while preserving them as the original requirement log.

## Requested behaviour

1. Put LUTs from these roots under the current project and organise them once.
2. Put LUTs of the same brand together, using honest folder/name/source evidence to classify them.
3. Mark LUTs from `code_ground/lut` as Codex-generated in Description.
4. Mark LUTs from `code_ground/claude lut` as Claude-generated in Description.
5. Mark LUTs from V-Log-Alchemy as coming from a GitHub project.
6. References for the remaining local collection will be supplied later; do not invent them.
7. Store and show Description in LUT detail.
8. Add Description as a LUT Manager column.
9. Classify Brand and Tags as separate metadata.
10. Keep the organised corpus inside this repository because it may later be managed in Git.
11. Treat Brand, Input Profile, and descriptive Tags as separate metadata. A Fujifilm-look LUT can still require Panasonic V-Log input.
12. Classify camera inputs at the useful profile level when evidence permits: ARRI LogC, Blackmagic Film, Canon C-Log variants, DJI D-Log, Fujifilm F-Log variants, GoPro Protune/GP-Log, Nikon N-Log, Panasonic NAT/STD/V-Log, RED Log3G10, and Sony S-Log variants.
13. The `code_ground` projects are predominantly camera-log LUTs. Use their README, CUBE header, folder, and filename evidence to determine the exact input; do not reduce every camera brand to Panasonic V-Log and do not treat the emulated-look brand as the input camera.
14. The Documents collection is mixed. Record `Unknown` when its input cannot be supported by explicit evidence rather than guessing.
15. Existing local records whose Brand is still `Unknown` should receive a one-time conservative Brand migration from an unambiguous physical folder or filename prefix; later user edits must win.
16. Import the downloaded multi-site collection, retain only LUTs the application can render, deduplicate exact transforms, and assign useful descriptive Tags.
17. Treat `CINECOLOR_*` packages, plus the adjacent `BEAUTY` and `INTERVIEW` packages carrying CINECOLOR installation documentation, as Brand `CINECOLOR` and preserve their pack names as Look folders.
18. Keep maker/visual Brand, Source pack, and Input Profile independent. In particular, SmallHD camera subfolders are Input evidence and do not turn the LUT maker into Canon, Sony, Panasonic, and so on.
19. Preserve separately authored Codex, Claude, V-Log-Alchemy, and downloaded implementations of the same named Look unless their transform fingerprints are exact duplicates.
20. When a downloaded package does not establish its input encoding or redistribution rights, record `Unknown`/pending explicitly rather than guessing.
21. Copy the current 79 Starred LUTs into a repository-local trial selection without adding duplicate records to the active Library.
22. Starred state must survive an application relaunch.
23. Keep Source independently visible so equally named Codex, Claude, V-Log-Alchemy, and downloaded implementations can be distinguished even when their Brand and LUT name are the same.
24. Remove meaningless folder wrappers from browsing where they only repeat provenance or packaging format, without rewriting the physical corpus or flattening arbitrary authored nesting.
25. Remove Codex-generated LUTs from the active corpus and keep Claude-generated LUTs.
26. Classify every remaining active LUT into exactly one measured colour family, including cyan/green and warm-brown/coffee families.
27. Expose those families as editable Collections rather than physical folders, Brand, Source, or ordinary Tags.
28. Seed each measured Collection once. If the user later removes membership or deletes a seeded Collection, rescanning must not recreate that authored choice.
29. Visual acceptance must launch the freshly built bundle from the current checkout by absolute path, must not reuse an already-running LUTzy process, and must expose branch/commit identity in the running window.
30. Use the Panasonic DC-S9 reference as LUT Library's default comparison sample without removing the existing fixed samples.
31. Clean filename-derived display labels non-destructively; preserve physical filenames and meaningful technical tokens, and qualify otherwise numeric labels with Brand or Source.
32. Hue angles are circular. No measured split angle may exceed 180 degrees, and changing the measurement rule must invalidate stale measured tags.
33. Do not delete the seeded colour Collections merely because the current coarse grouping needs review; relaunch with the Panasonic sample and let the user assess the corrected, current build first.
34. Superseding item 24 for the repository corpus: remove generic provenance and packaging wrappers from the actual physical `LUTLibrary/LUTs` tree, including `Documents Collection`, repeated Brand/Source names, `3dlut`, grid-size, range, and export-tool-only layers. Preserve meaningful authored pack/family nesting and every CUBE byte.
35. Treat the manifest/catalog as the durable metadata database for Source, Description, Brand, Input Profile, Tags, provenance, and duplicate identity. LUT Manager is the table/Inspector surface for that metadata; physical folders do not need to repeat it.

Reference screenshot: `/var/folders/pt/8st82qw57rs05k145xw2_5w40000gn/T/codex-clipboard-8b3bb8db-be22-4d9c-95f5-bebf66cec92e.png`.

Input-profile reference screenshot: `/Users/world4jason/Desktop/Screenshot 2026-08-27 at 12.45.20 PM.png`.

Existing-Brand migration reference screenshot: `/var/folders/pt/8st82qw57rs05k145xw2_5w40000gn/T/codex-clipboard-5ddf0a3a-b72c-47fe-b49e-c13e80d0e57a.png`.

Starred-selection and folder/source-disambiguation references:

- `/var/folders/pt/8st82qw57rs05k145xw2_5w40000gn/T/codex-clipboard-eab3b8da-d75a-40ba-902b-4f740ae922fa.png`
- `/var/folders/pt/8st82qw57rs05k145xw2_5w40000gn/T/codex-clipboard-8cf00710-b67f-4245-a3b3-0bea0083442b.png`
- `/var/folders/pt/8st82qw57rs05k145xw2_5w40000gn/T/codex-clipboard-e9505ce7-1344-4b2e-9000-895232c9c745.png`
