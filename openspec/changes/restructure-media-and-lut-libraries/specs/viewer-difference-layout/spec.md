## ADDED Requirements

### Requirement: Contextual Difference layout
Viewer Difference mode SHALL keep both compared LUT renders visible beside the amplified difference map instead of replacing the complete preview with the difference map alone.

#### Scenario: Enter Difference mode
- **WHEN** the user selects Difference as the Viewer comparison layout
- **THEN** A appears in the upper-left region, B appears in the lower-left region, and DIFF spans the full-height right region

#### Scenario: Identify the compared renders
- **WHEN** Difference mode has a chosen base LUT and a current LUT
- **THEN** A names and renders the chosen base LUT, B names and renders the current LUT, and DIFF states the amplification and that black means identical

#### Scenario: Change either compared LUT
- **WHEN** the user changes A through its LUT picker or changes B through the Viewer LUT Gallery
- **THEN** the corresponding reference render and the difference map update in place without leaving Difference mode

#### Scenario: A and B finish rendering out of order
- **WHEN** an image, develop, adjustment, intensity, or LUT change schedules replacement A and B renders and one side finishes before the other
- **THEN** DIFF remains unavailable until both current renders are present and never combines a new render with the previous render from the other side

### Requirement: Difference render continuity
The contextual Difference layout SHALL reuse the existing Viewer render results and DifferenceComposer calculation rather than introduce a separate colour or LUT path.

#### Scenario: Compare identical renders
- **WHEN** A and B resolve to identical rendered pixels
- **THEN** the DIFF region remains black under the existing amplification contract while A and B remain visible
