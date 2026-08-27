## ADDED Requirements

### Requirement: LUT records preserve Description metadata

The catalog SHALL persist an optional user-editable Description independently from Name, Brand / Source, Tags, folder, Collections, Starred state, and transform bytes.

#### Scenario: Decode an older catalog

- **WHEN** a catalog snapshot created before Description support is loaded
- **THEN** every record decodes successfully with an empty Description

#### Scenario: Edit Description

- **WHEN** the user edits a LUT Description in Manager and relaunches
- **THEN** the Description remains attached to the same durable LUT record without changing the `.cube` file

### Requirement: Manifest metadata seeds a record once

The catalog SHALL apply matching curated Brand, descriptive Tags, and Description when a manifest-backed record is first encountered, and SHALL NOT overwrite subsequent user edits during later scans.

#### Scenario: First manifest-backed scan

- **WHEN** a new record fingerprint matches a curated manifest entry
- **THEN** its Brand, Tags, and Description are initialised and the seed is recorded

#### Scenario: Rescan after user edit

- **WHEN** the user changes or clears seeded metadata and the same manifest is scanned again
- **THEN** the user's current catalog values remain unchanged

### Requirement: Manager exposes Description at table and Inspector scale

LUT Manager SHALL show Description as a table column and SHALL allow Description editing in the persistent Inspector.

#### Scenario: Inspect one LUT

- **WHEN** one LUT is selected
- **THEN** the Inspector shows its complete Description and can save or clear it

#### Scenario: Inspect multiple LUTs

- **WHEN** multiple LUTs with different Descriptions are selected
- **THEN** the Inspector communicates a mixed value and changes the selection only through an explicit batch apply action

### Requirement: LUT Library detail explains provenance

LUT Library detail SHALL display a non-empty Description in its metadata panel without treating the prose as a Tag.

#### Scenario: Open a described LUT

- **WHEN** a LUT with Description metadata is opened in visual detail
- **THEN** the complete Description appears near Brand / Source and transform facts while Gallery card density remains unchanged

