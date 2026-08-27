# Design: repository-local curated LUT corpus and Description metadata

## Corpus layout

The repository owns a top-level `LUTLibrary/` workspace:

```text
LUTLibrary/
  LUTs/                         active, renderable, unique 3D LUTs
    .lutzy-library.json         metadata sidecar
    <Brand>/<Source>/…/*.cube
  Unsupported/                  retained outside the active scan root
  README.md                     regeneration and Git/LFS guidance
  SOURCE_AUDIT.md               source, license, exclusion, and tally audit
```

The physical hierarchy answers where a transform belongs and where it came from. Brand remains a dedicated catalog namespace and does not become an ordinary Tag. A source subfolder prevents two independently generated looks with the same target brand from being conflated.

Downloaded packs keep the same separation. `CINECOLOR_*`, plus packages carrying CINECOLOR's own installation document, use Brand `CINECOLOR`. Other packages use an evidenced maker or a stable pack-family label rather than pretending an input-camera folder is the maker. For example, SmallHD's multi-camera Movie Looks stay Brand `SmallHD`, Source `SmallHD Movie Looks 2`, while Canon/Sony/Panasonic folder names become precise Input Profiles. A Fujifilm visual family may therefore contain separately sourced Codex, Claude, and V-Log-Alchemy implementations without flattening Source into Brand or ordinary Tags.

## Canonicalisation

The curator considers only `.cube` inputs. A candidate must contain a supported 3D size and parse through the same `CubeLUT` implementation used by the application before entering `LUTs/`. Exact SHA-256 duplicates keep one deterministic canonical file; the audit records skipped source paths. Unsupported 1D or unreadable inputs remain outside `LUTs/` and are reported rather than silently disappearing.

Only exact transform fingerprints deduplicate. Similar names, the same target Look, or independently authored implementations remain separate when their transform fingerprints differ.

Generated projects use their documented canonical output, not every historical release, staging directory, SD-card short-name copy, calibration derivative, archive, virtual environment, or test fixture. This prevents release history from masquerading as distinct looks.

The curation operation is reproducible and does not mutate or delete any supplied source directory.

## Manifest contract

`.lutzy-library.json` is versioned and contains:

- source definitions with stable IDs, labels, descriptions, reference URLs or local-reference status, and license status;
- one entry per active canonical LUT with relative path, SHA-256 fingerprint, Brand value, Input Profile, descriptive Tags, and a source ID;
- audit information for duplicates and unsupported candidates.

The SHA-256 fingerprint is the durable join. Import may rename a file to avoid a basename collision, and the user may later move it between physical folders, without losing the seed metadata.

## Catalog seeding

`LUTRecord` gains an optional `descriptionText` and an optional manifest-seed marker. Old snapshots decode with nil values.

After a scan reconciles physical LUTs, the library loads any valid `.lutzy-library.json` sidecars under the scanned root and offers matching fingerprint metadata to the catalog. The catalog applies a manifest entry at most once to a record:

- Description is seeded from the source or entry description.
- Brand is seeded into the dedicated `LUTOrigin` namespace.
- Input Profile is seeded as dedicated record metadata. It describes what image encoding the LUT expects, and is not inferred from the emulated-look Brand or stored as an ordinary Tag.
- Tags are seeded into record-level typed Tags, excluding internal `input:*` values.
- A seed marker records that the manifest was considered.

Once seeded, later scans never overwrite user changes. A malformed or unsupported manifest cannot prevent ordinary LUT scanning.

## Input-profile evidence and runtime boundary

The curator records the most specific defensible input profile, using evidence in this order: an explicit CUBE photo-style/header declaration, an upstream per-file or package contract, then an unambiguous filename or containing folder. Conflicting or absent evidence becomes `Unknown`. The profile vocabulary is human-readable and extensible because vendor generations such as C-Log 1/2/3, F-Log/F-Log2, and S-Log2/S-Log3 are operationally distinct.

Brand describes the maker or visual family being organised. Input Profile describes the encoded pixels the transform accepts. For example, Codex/Claude Fujifilm-look files remain Brand `Fujifilm` with Input Profile `Panasonic V-Log`; V-Log-Alchemy `*S2V` adapters are Brand `Panasonic` with Input Profile `Panasonic STD`.

`CubeLUT.inputSpace` remains the rendering pipeline's current coarse adapter choice. Manifest Input Profile is truthful catalog metadata and does not silently pretend LUTzy implements every vendor log-to-display adapter. Panasonic V-Log keeps the existing automatic V-Log route; other camera-log profiles are presented explicitly instead of being mislabeled as Display.

## Conservative legacy Brand migration

Existing catalog records may predate Brand metadata even when their physical top-level folder or filename starts with an unambiguous known brand. After reconcile and manifest seeding, a one-time migration fills only `Unknown` Brand values from this narrow mapping. It records that inference was applied so a later deliberate user change to `Unknown` is not undone. Ambiguous folders and names remain `Unknown`.

"Considered" is recorded for every first-pass record, including a record that already has a manifest-seeded, Custom, or vendor Brand. Otherwise changing that Brand to `Unknown` later would incorrectly reopen the compatibility migration.

## Scalable scan contract

Current manifests also carry an optional SHA-256 of the exact CUBE file bytes. For a matching file, discovery authenticates that cheap raw digest, reads only the header, and uses the manifest's normalized transform fingerprint. The float table is reparsed only when a render, profiler, or inspector actually needs it; the renderer's existing eight-entry LRU bounds retained Core Image filters. Old manifests or changed files use the complete parser.

Outside-root catalog loads and newly saved derived LUTs are the deliberate exception: they parse while a security scope or Save panel grant is active and retain that single table, because lazy file access would occur after the sandbox grant closes.

Curated descriptive Tags do not replace objective measured tags or similarity metrics. After discovery publishes, profiling proceeds in small background batches. Completed batches enter the existing persistent tag index; replacing the library cancels both the coordinating task and its current detached parser before beginning the next pass.

A lazy LUT materializes into one immutable table before rendering or profiling. Materialization verifies that the parsed transform fingerprint still matches the scan-time fingerprint; an in-place replacement is rejected until the next scan reconciles its new identity. Profiling reuses that one materialized table for every probe rather than reparsing the source for each metric. Star and typed-Tag actions create an explicitly unmeasured placeholder instead of parsing a file synchronously on the main actor; the ordinary background profiler later replaces it.

Inspector and Editor use a shared four-entry materialized-table LRU. Cache misses are serialized on the cache actor, bounding parsing to one LUT globally while preserving caller cancellation; Inspector stores the sampled curve instead of sampling from SwiftUI body, and Editor retains prepared base/stack tables so slider ticks only bake from memory. Every scan re-prepares an active Editor from the latest fingerprint and metadata. This bounds common memory to four active UI tables while keeping large text parsing off the main actor.

The library owns the detached scan worker directly. Replacing a scan cancels that worker and advances a generation token, so an obsolete result can neither consume another complete scan nor publish over a newer folder.

## Import

Folder import continues to copy renderable `.cube` files. When a selected folder contains a valid `.lutzy-library.json`, import copies the sidecar beside the copied hierarchy. The normal post-copy scan then performs metadata seeding. Generic folders without a sidecar behave exactly as before.

## Description editing and presentation

LUT Manager exposes Description as a table column so missing provenance is visible at list scale. The Inspector edits one Description directly and applies an explicit batch Description only when the user asks; it does not infer content from a filename. LUT Library detail displays a non-empty Description beneath the core transform facts.

Description is prose provenance/context. It is not a Brand, Tag, filename, transform comment, or colour-processing instruction.

## Git boundary

The corpus is prepared inside the repository, but the initial implementation does not silently commit gigabytes of third-party assets or invent redistribution permission. `SOURCE_AUDIT.md` makes pending references explicit. Git LFS or another binary policy can be adopted when the user chooses to publish the corpus.
