## ADDED Requirements

### Requirement: Repository-local corpus preserves honest organisation and provenance

The project SHALL provide a reproducible repository-local LUT corpus whose active LUTs are renderable unique 3D transforms physically grouped by Brand and Source, without modifying the supplied source directories or third-party LUT bytes.

#### Scenario: Curate generated and third-party sources

- **WHEN** the curator processes the six supplied source roots
- **THEN** it selects documented canonical outputs, groups active LUTs under `<Brand>/<Source>`, and records the source path and provenance of every canonical LUT

#### Scenario: Curate downloaded multi-site packs

- **WHEN** a downloaded CUBE file parses through the application's supported 3D LUT path
- **THEN** it is grouped by evidenced Brand and Source pack, receives an evidence-based Input Profile plus descriptive Tags, and remains separately addressable unless its transform fingerprint is an exact duplicate

#### Scenario: Organise CINECOLOR packages

- **WHEN** a package is named `CINECOLOR_*` or carries CINECOLOR's installation document
- **THEN** Brand is `CINECOLOR`, Source is the CINECOLOR collection, and its cleaned package name remains visible as the Look folder

#### Scenario: Organise a multi-camera vendor pack

- **WHEN** SmallHD Movie Looks contains the same creative Look for several camera-log folders
- **THEN** Brand remains `SmallHD`, Source remains `SmallHD Movie Looks 2`, and each camera folder determines the corresponding Input Profile rather than the Brand

#### Scenario: Preserve separately authored versions

- **WHEN** Codex, Claude, V-Log-Alchemy, or another source provides a similarly named Look with a different transform fingerprint
- **THEN** every distinct implementation remains active under its own Source path

#### Scenario: Encounter an exact duplicate

- **WHEN** two candidates have the same SHA-256 fingerprint
- **THEN** the active corpus stores one deterministic canonical copy and records the skipped path in the audit

#### Scenario: Encounter an unsupported transform

- **WHEN** a candidate is a 1D LUT or cannot be rendered by `CubeLUT`
- **THEN** it does not enter the active scan root and its exclusion reason remains visible in the corpus audit

### Requirement: Curated metadata travels beside LUT bytes

The active corpus SHALL contain a versioned `.lutzy-library.json` manifest keyed by SHA-256 fingerprint with source, Brand, Input Profile, Tags, Description provenance, and relative path metadata.

#### Scenario: File is renamed during import

- **WHEN** managed-library import renames a curated LUT to avoid a basename collision
- **THEN** its manifest metadata still resolves through the unchanged SHA-256 fingerprint

#### Scenario: Reference is not yet known

- **WHEN** a source has no confirmed reference supplied by the user
- **THEN** its source record says that the reference is pending and does not invent a vendor, author, URL, or license

### Requirement: Input Profile is classified independently and conservatively

Every active manifest entry SHALL record the most specific defensible Input Profile independently of Brand and ordinary Tags.

#### Scenario: Emulated brand differs from input encoding

- **WHEN** a Fujifilm-look Codex or Claude LUT is authored for Panasonic V-Log/V-Gamut pixels
- **THEN** Brand is `Fujifilm` and Input Profile is `Panasonic V-Log`

#### Scenario: Panasonic Standard adapter

- **WHEN** a V-Log-Alchemy conversion file declares `#LUMIXPHOTOSTYLE STD`
- **THEN** Input Profile is `Panasonic STD` rather than Panasonic V-Log or Display

#### Scenario: Mixed local collection has insufficient evidence

- **WHEN** no header, upstream contract, folder, or filename establishes the input encoding without conflict
- **THEN** Input Profile is `Unknown` and the curator does not infer it from Brand alone

#### Scenario: Package folder declares a Rec.709 input

- **WHEN** a Documents LUT is inside a package folder named `Rec.709 to Color Grading LUTs`
- **THEN** Input Profile is `Display / Rec.709` even when the creative LUT filename has no profile token

### Requirement: Legacy records receive conservative one-time Brand repair

The catalog SHALL repair an `Unknown` Brand once when a known physical top-level folder or filename prefix is unambiguous, without overwriting authored metadata.

#### Scenario: Existing Fuji folder has no Brand

- **WHEN** an existing record in physical folder `fuji` still has Brand `Unknown`
- **THEN** it becomes Brand `Fujifilm`

#### Scenario: User later clears or changes Brand

- **WHEN** the one-time migration has already considered that record
- **THEN** later scans do not restore the inferred Brand over the user's choice

#### Scenario: Record already has seeded or authored Brand

- **WHEN** the migration first considers a manifest-seeded, Custom, or vendor Brand
- **THEN** it records that consideration without changing the Brand, so a later authored `Unknown` remains `Unknown`

### Requirement: Folder import preserves curated sidecars

Importing a folder SHALL preserve a valid `.lutzy-library.json` sidecar so the ordinary post-import scan can seed metadata.

#### Scenario: Import curated corpus

- **WHEN** the user imports a folder containing renderable LUTs and a valid curated sidecar
- **THEN** the LUTs and sidecar are copied into the managed hierarchy and the imported records receive the matching metadata

#### Scenario: Import ordinary folder

- **WHEN** the user imports a folder without a curated sidecar
- **THEN** existing import, deduplication, naming, and review behaviour remains unchanged

### Requirement: Large curated corpora scan with bounded memory and cancellation

The library SHALL authenticate current curated file bytes against the sidecar, discover valid LUT metadata without retaining every 3D float table, and cancel an obsolete scan worker before starting its replacement.

#### Scenario: Scan an unchanged curated corpus

- **WHEN** an entry's raw-file SHA-256 matches its sidecar
- **THEN** discovery uses the authenticated content fingerprint and header without retaining its RGBA cube table

#### Scenario: Curated LUT is modified without updating the sidecar

- **WHEN** raw-file SHA-256 no longer matches the sidecar
- **THEN** the library falls back to the complete parser rather than trusting stale metadata

#### Scenario: LUT security scope ends before rendering

- **WHEN** an outside-root catalog record or newly saved derived LUT is parsed under temporary sandbox access
- **THEN** that live LUT retains its table and remains renderable after the security scope closes

#### Scenario: Lazy LUT changes after discovery

- **WHEN** a lazy file-backed LUT is replaced in place after its scan-time fingerprint was recorded
- **THEN** materialization rejects the mismatched transform until a rescan reconciles the new fingerprint, Brand, Tags, and pixels

#### Scenario: Scan is replaced

- **WHEN** another folder scan starts before the current scan completes
- **THEN** the actual background worker receives cancellation and only the newest generation may publish

#### Scenario: Manifest uses uppercase SHA-256

- **WHEN** a valid sidecar encodes a SHA-256 fingerprint with uppercase hex
- **THEN** metadata lookup normalizes the key and still seeds the matching record

#### Scenario: Curated corpus still needs objective measurement

- **WHEN** manifest metadata has seeded Brand, Input Profile, Tags, and Description
- **THEN** objective colour, contrast, saturation, and similarity metrics continue in cancellable persisted background batches rather than being skipped or blocking discovery

#### Scenario: Inspector and Editor use a lazy LUT repeatedly

- **WHEN** Inspector draws a response curve or Editor refreshes after slider changes
- **THEN** the LUT is materialized off the main actor with globally bounded parse concurrency and reused through a bounded cache rather than reparsed from disk in SwiftUI body or on every slider tick

#### Scenario: Editor LUT changes during a rescan

- **WHEN** a scan changes the fingerprint, name, location, or Input Profile behind the Editor's durable record
- **THEN** Editor discards its resident base/stack tables and prepares the latest post-scan records before baking again
