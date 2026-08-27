## ADDED Requirements

### Requirement: Arbitrary folder nesting
Viewer SHALL retain every component of a LUT's relative physical folder path and support it without a product-defined maximum depth. Navigation MAY suppress a narrow explicit set of non-semantic provenance/format wrappers and repeated ancestor labels, but SHALL NOT rewrite the physical path or flatten arbitrary authored nesting.

#### Scenario: Scan a deeply nested LUT
- **WHEN** a LUT exists at a path containing twelve nested folders
- **THEN** the Viewer hierarchy contains twelve addressable folder nodes in the same order

#### Scenario: Select an intermediate folder
- **WHEN** the user selects any non-leaf folder
- **THEN** the contact sheet contains LUTs from that folder and every depth below it

#### Scenario: Hide known packaging wrappers

- **WHEN** a path contains a repeated Brand/Source label or a known wrapper such as `Documents Collection/3dlut/.../full-to-full-range`
- **THEN** navigation hoists the meaningful descendant folders, while each visible node still selects its complete original physical path and recursive LUT scope

#### Scenario: Preserve arbitrary authored levels

- **WHEN** nested folder names are not in the explicit wrapper vocabulary
- **THEN** every authored level remains visible and addressable regardless of whether it has only one child

### Requirement: Independent disclosure and selection
Expanding or collapsing a branch SHALL NOT change the selected LUT scope, and selecting a folder SHALL NOT require clicking its disclosure control.

#### Scenario: Expand a package
- **WHEN** the user clicks a collapsed branch's chevron
- **THEN** its immediate children become visible and the current contact sheet remains unchanged

#### Scenario: Select a package row
- **WHEN** the user clicks the folder name or row
- **THEN** that folder becomes selected without toggling its disclosure state

### Requirement: Legible deep-tree defaults
Viewer SHALL initially reveal top-level package contents, keep deeper branches compact, and reveal the ancestors of a restored or newly selected descendant.

#### Scenario: Open a large library
- **WHEN** the folder tree first appears
- **THEN** top-level branches are expanded and nested branches are collapsed unless they contain the selected folder

#### Scenario: Restore a deep folder selection
- **WHEN** a saved selected folder is below collapsed ancestors
- **THEN** every ancestor expands until the selected row is visible

### Requirement: Recursive folder counts
Every folder row SHALL show the number of LUTs returned by selecting that folder, including all descendant depths.

#### Scenario: Count a parent package
- **WHEN** LUTs exist directly inside a parent and in several nested descendants
- **THEN** the parent's count equals the total across the complete subtree
