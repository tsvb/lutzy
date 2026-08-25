## ADDED Requirements

### Requirement: Durable per-file LUT records
Every on-disk LUT SHALL have a durable LUTRecordID that is independent of file path and content fingerprint, and every separately present file SHALL have a distinct record even when contents are identical.

#### Scenario: Scan identical files
- **WHEN** two LUT files at different locations contain identical transform data
- **THEN** they receive different LUTRecordIDs and can hold different display names, origins, typed tags, Starred states, and Collection memberships

#### Scenario: Rescan known locator
- **WHEN** the library rescans a file at a known locator
- **THEN** the existing LUTRecordID is reused rather than minted again

### Requirement: Identity-preserving file movement
Manager-controlled move or rename operations SHALL retain LUTRecordID and SHALL update the catalog locator without publishing a second identity.

#### Scenario: Move through Manager
- **WHEN** Manager successfully moves a LUT into another physical folder
- **THEN** its record ID, document references, grid-cell references, metadata, and Collection memberships remain unchanged

#### Scenario: Catalog update cannot complete
- **WHEN** a file operation cannot be reconciled with a durable catalog update
- **THEN** the operation reports failure and does not expose old and new locators as two records

### Requirement: Conservative scan reconciliation
The catalog SHALL retain unavailable records and SHALL reconnect an unmatched file by content fingerprint only when exactly one unavailable record is a candidate.

#### Scenario: Unique external move
- **WHEN** one record is unavailable and exactly one unmatched file has the same fingerprint
- **THEN** the file adopts that record ID and all record-level metadata is restored

#### Scenario: Ambiguous duplicate content
- **WHEN** zero or multiple unavailable records share the unmatched file's fingerprint
- **THEN** the file receives a new LUTRecordID and no unavailable record is deleted or merged automatically

### Requirement: Explicit metadata identity levels
User-authored metadata SHALL be stored per LUTRecordID, while measured metrics and measured tags MAY be shared per content fingerprint.

#### Scenario: Edit one duplicate
- **WHEN** the user changes a typed tag, origin, display-name override, Starred state, or Collection membership on one of two identical-content records
- **THEN** the other record remains unchanged

#### Scenario: Measure identical transforms
- **WHEN** two records have the same content fingerprint
- **THEN** they may reuse the same measured metrics and measured tags because those describe the transform rather than the record

### Requirement: Legacy LUT metadata migration
Migration SHALL create one record per scanned file, copy legacy content-hash typed tags and favourite state to every matching record, preserve measured data at content level, and never collapse identical files.

#### Scenario: Migrate duplicate legacy LUTs
- **WHEN** two legacy LUT files have the same content hash and one legacy metadata entry
- **THEN** two records are created and each initially receives copies of the legacy typed tags and favourite state

### Requirement: Durable document and session references
Viewer documents, selected LUT state, and comparison-grid cells SHALL persist LUTRecordID for on-disk LUTs and SHALL migrate an old path reference only through an exact scanned locator match.

#### Scenario: Relaunch after Manager move
- **WHEN** a referenced LUT was moved through Manager and the app relaunches
- **THEN** Viewer and every comparison cell resolve the same LUT record through its updated locator

#### Scenario: Unresolved legacy path
- **WHEN** an old path reference has no exact scanned locator during migration
- **THEN** it remains a non-destructive missing reference and does not select a content-identical substitute

