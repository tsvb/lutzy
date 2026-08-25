## ADDED Requirements

### Requirement: Distinct LUT source types
Viewer and LUT Manager SHALL present physical Folders, manual Collections, and the built-in Starred source as visibly distinct groups.

#### Scenario: Browse physical hierarchy
- **WHEN** the user expands Folders
- **THEN** the recursively nested physical LUT hierarchy and descendant-inclusive counts are available

#### Scenario: Browse virtual sources
- **WHEN** the user views Collections or Starred
- **THEN** those sources are shown outside the physical folder hierarchy and do not imply filesystem locations

### Requirement: Manual collection creation
LUT Manager SHALL let the user create a non-empty named Collection from one or more selected LUTs without moving or copying any LUT file.

#### Scenario: Create a cross-folder collection
- **WHEN** the user selects LUTs from different camera-brand folders and creates “Low Saturation”
- **THEN** one virtual Collection contains those LUTs while every LUT remains in its original physical folder

#### Scenario: Create an empty-name collection
- **WHEN** the proposed Collection name contains only whitespace
- **THEN** creation is rejected without changing membership metadata

### Requirement: Many-to-many membership
A LUT SHALL be able to belong to multiple Collections, and adding or removing membership SHALL affect only metadata.

#### Scenario: Add a LUT to another collection
- **WHEN** a LUT already belongs to one Collection and is added to a second
- **THEN** it remains in both Collections and its physical file is unchanged

#### Scenario: Remove membership
- **WHEN** the user removes a LUT from a Collection
- **THEN** the LUT disappears from that Collection but remains in the library, its folder, other Collections, and Starred state

### Requirement: Safe collection deletion
Deleting a Collection SHALL delete only the Collection definition and membership metadata.

#### Scenario: Delete collection
- **WHEN** the user confirms deletion of a Collection
- **THEN** no LUT file, tag, favourite flag, or other Collection membership is removed

### Requirement: Collection structure editing in Manager
LUT Manager SHALL provide create, rename, delete, add-member, and remove-member actions for Collections, including batch membership changes for selected LUTs.

#### Scenario: Rename collection
- **WHEN** the user gives a Collection a valid new name in LUT Manager
- **THEN** its identity and memberships remain unchanged while every source list displays the new name

#### Scenario: Batch membership edit
- **WHEN** the user selects multiple LUTs in Manager and adds or removes an existing Collection membership
- **THEN** the change applies to exactly the selected LUTs without changing files, folders, tags, or Starred state

### Requirement: Stable membership across library changes
Collection membership SHALL use stable LUT identity so a rename or move preserves membership, and temporarily unavailable LUTs SHALL NOT be silently removed from collection metadata.

#### Scenario: Move a member LUT
- **WHEN** a Collection member is moved to another physical folder through LUT Manager
- **THEN** it remains a member of the Collection

#### Scenario: Reconnect a missing LUT
- **WHEN** a previously unavailable member becomes available again after a library rescan or reconnection
- **THEN** its Collection membership is restored without manual re-adding

### Requirement: Starred remains built in
Starred SHALL remain a single non-deletable source derived from the existing favourite flag and SHALL NOT be stored as a user Collection.

#### Scenario: Star a LUT
- **WHEN** the user stars a LUT from Viewer or LUT Manager
- **THEN** the LUT appears in Starred without being added to any Collection
