## Why

The same source image and LUT currently produce different original RGB values and different graded colours in LUTzy and `lut-viewer`. A colour tool cannot be trusted until those differences are measured, explained, and removed wherever both applications claim the same rendering contract.

## What Changes

- Add a reproducible cross-application colour comparison using shared images, LUTs, pixel probes, and image-difference metrics.
- Define the canonical decode, neutral-render, LUT-input, interpolation, and output-encoding contract for standard images.
- Separate standard-image parity from RAW parity, whose Apple Core Image and `rawpy` demosaic paths may require an explicit compatibility boundary.
- Align LUTzy with the canonical contract and add regression checks for the corrected path.
- Preserve a safe fallback when a required V-Log conversion cannot be constructed.

## Capabilities

### New Capabilities

- `cross-app-color-parity`: Defines measurable RGB and LUT-render agreement between LUTzy and `lut-viewer`, including explicit standard-image and RAW boundaries.

### Modified Capabilities

None.

## Impact

The change affects `RenderPipeline`, `VLogInputAdapter`, source decoding and render verification in LUTzy; the comparison harness also reads the `lut-viewer`/`lutcraft` reference pipeline. It introduces no third-party dependency to LUTzy and does not change the macOS 14 deployment target.
