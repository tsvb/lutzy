## ADDED Requirements

### Requirement: Persistent metadata Inspector
LUT Manager SHALL provide a persistent right-side Inspector for selected LUT metadata instead of requiring a modal sheet for normal tag and metadata editing.

#### Scenario: No selection
- **WHEN** no LUT is selected in Manager
- **THEN** the Inspector shows a stable instructional empty state without editable stale values

#### Scenario: Select one LUT
- **WHEN** the user selects one LUT
- **THEN** the Inspector displays its name, Vendor/Custom/Unknown origin, tags, Collection memberships, physical folder, and Starred state

### Requirement: Direct tag editing
The Inspector SHALL display existing tags as individually removable chips and SHALL provide direct tag addition without opening the current add-only Tag sheet.

#### Scenario: Remove existing tag
- **WHEN** the user removes a tag chip from a selected LUT
- **THEN** that tag is removed from the LUT metadata and the table, visual Library card, filters, and detail update consistently

#### Scenario: Add tag
- **WHEN** the user enters a valid new tag in the Inspector
- **THEN** the tag is persisted once, appears as a chip, and does not create a duplicate value

### Requirement: Single-selection metadata editing
For one selected LUT, the Inspector SHALL allow editing of a record-level display-name override, origin, typed tags, Collection membership, physical folder, and Starred state.

#### Scenario: Set display-name override
- **WHEN** the user enters a non-empty display name
- **THEN** the override persists by LUTRecordID, all UI uses it, and the physical `.cube` filename remains unchanged

#### Scenario: Clear display-name override
- **WHEN** the user clears or resets the display-name override
- **THEN** UI falls back to the current filename-derived LUT name after rescan and relaunch

#### Scenario: Edit origin and collection
- **WHEN** the user assigns a vendor and changes Collection membership
- **THEN** both metadata changes persist against stable LUT identity without changing the LUT transform

#### Scenario: Move physical folder
- **WHEN** the user chooses another physical folder in the Inspector
- **THEN** Manager performs the existing file move semantics and retains tags, origin, Starred state, and Collection memberships

### Requirement: Multi-selection metadata editing
For multiple selected LUTs, the Inspector SHALL distinguish common, absent, and mixed metadata values and SHALL provide explicit batch add/remove actions only for fields with safe batch meaning.

#### Scenario: Inspect mixed tags
- **WHEN** selected LUTs do not all share the same tags or Collection memberships
- **THEN** the Inspector communicates the mixed state without claiming that every displayed value applies to every LUT

#### Scenario: Batch add tag
- **WHEN** the user adds a tag to a multi-selection
- **THEN** the tag is added to every selected LUT, remains unique per LUT, and no unselected LUT changes

#### Scenario: Unsafe batch field
- **WHEN** multiple LUTs are selected
- **THEN** display-name editing and any other field without defined batch semantics are disabled rather than applying an ambiguous change

### Requirement: Metadata-only Manager editing
LUT Manager SHALL edit descriptive metadata and organisation without exposing controls that change LUT colour values or transforms; LUT Editor SHALL remain the exclusive destination for transform editing.

#### Scenario: Edit LUT metadata
- **WHEN** the user changes a LUT name, origin, tags, Collection membership, folder, or Starred state in Manager
- **THEN** the LUT's rendered transform remains byte-for-byte or value-for-value unchanged

#### Scenario: Request transform editing
- **WHEN** the user chooses to alter LUT colour values, curves, interpolation, or the transform itself
- **THEN** the application routes the action to LUT Editor rather than performing it in Manager
