## ADDED Requirements

### Requirement: Stage-labelled colour comparison
The system SHALL distinguish decoded source, neutral base, and graded output when comparing LUTzy with `lut-viewer`.

#### Scenario: Original source comparison
- **WHEN** an ungraded standard sRGB image is compared across applications
- **THEN** the comparison uses decoded-source pixels and MUST NOT substitute a neutral LUT render for the original

#### Scenario: Neutral base comparison
- **WHEN** a neutral base render is compared
- **THEN** both applications use the ordinary-photo-to-V-Log conversion followed by the same neutral LUT and interpolation mode

### Requirement: Standard-image parity fixture
The repository SHALL contain deterministic golden vectors for ordinary sRGB conversion and representative LUT output, including the interpolation and encoding used to generate them.

#### Scenario: Adapter parity
- **WHEN** the Core Image adapter receives a golden sRGB sample
- **THEN** its V-Log/V-Gamut output matches the expected vector within the recorded tolerance

#### Scenario: Full pipeline parity
- **WHEN** a golden sample is rendered through the specified LUT with trilinear interpolation
- **THEN** the sRGB output matches the reference result within the recorded tolerance

### Requirement: Safe adaptation failure
The render pipeline MUST NOT feed display-referred values directly into a V-Log LUT when V-Log adaptation fails.

#### Scenario: Adapter cannot be created
- **WHEN** the V-Log adaptation kernel cannot compile or apply
- **THEN** the pipeline returns the ungraded image instead of applying the LUT to invalid input

### Requirement: Interpolation-aware claims
Cross-application colour claims SHALL identify the cube interpolation mode.

#### Scenario: Different interpolation modes
- **WHEN** the viewer uses tetrahedral interpolation and LUTzy uses trilinear interpolation
- **THEN** any pixel difference is reported as an interpolation-bound comparison rather than a parity failure

### Requirement: RAW decoder boundary
The system SHALL report RAW cross-application output as decoder-dependent while LUTzy uses `CIRAWFilter` and the viewer uses `rawpy`.

#### Scenario: Same RAW in both applications
- **WHEN** the same RAW file is rendered by LUTzy and `lut-viewer`
- **THEN** each application verifies preview/export consistency but the acceptance result MUST NOT claim cross-application pixel identity
