## ADDED Requirements

### Requirement: Repository-local corpus preserves honest organisation and provenance

The project SHALL provide a reproducible repository-local LUT corpus whose active LUTs are renderable unique 3D transforms physically grouped by Brand and Source, without modifying the supplied source directories or third-party LUT bytes.

#### Scenario: Curate generated and third-party sources

- **WHEN** the curator processes the five supplied source roots
- **THEN** it selects documented canonical outputs, groups active LUTs under `<Brand>/<Source>`, and records the source path and provenance of every canonical LUT

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

### Requirement: Legacy records receive conservative one-time Brand repair

The catalog SHALL repair an `Unknown` Brand once when a known physical top-level folder or filename prefix is unambiguous, without overwriting authored metadata.

#### Scenario: Existing Fuji folder has no Brand

- **WHEN** an existing record in physical folder `fuji` still has Brand `Unknown`
- **THEN** it becomes Brand `Fujifilm`

#### Scenario: User later clears or changes Brand

- **WHEN** the one-time migration has already considered that record
- **THEN** later scans do not restore the inferred Brand over the user's choice

### Requirement: Folder import preserves curated sidecars

Importing a folder SHALL preserve a valid `.lutzy-library.json` sidecar so the ordinary post-import scan can seed metadata.

#### Scenario: Import curated corpus

- **WHEN** the user imports a folder containing renderable LUTs and a valid curated sidecar
- **THEN** the LUTs and sidecar are copied into the managed hierarchy and the imported records receive the matching metadata

#### Scenario: Import ordinary folder

- **WHEN** the user imports a folder without a curated sidecar
- **THEN** existing import, deduplication, naming, and review behaviour remains unchanged
