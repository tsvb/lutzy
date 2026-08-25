## Context

LUTzy and `lut-viewer` do not currently show equivalent pipeline stages. LUTzy's “Original” is the source decoded by Core Image. The viewer's split-view base is a V-Log conversion followed by `utility-vlog-neutral.cube`; it is intentionally labelled “neutral base” and is not an identity transform for saturated or clipped colours. The applications also use different default cube interpolation (`CIColorCube` trilinear versus viewer tetrahedral) and different implementations of the display-to-scene inverse.

RAW adds a separate incompatibility: LUTzy uses `CIRAWFilter`, while the viewer uses `rawpy`, an embedded-JPEG exposure match, and its own downsampler. Those decoders cannot be made pixel-identical without replacing one application's RAW pipeline or introducing a forbidden dependency.

## Goals / Non-Goals

**Goals:**

- Name and compare equivalent stages rather than treating source and neutral base as the same image.
- Make standard sRGB input conversion and trilinear LUT output reproducible against shared golden vectors.
- Verify the actual Core Image adapter, cube, and output decode path rather than only scalar helper maths.
- Fail safely when V-Log adaptation cannot be created.
- Quantify and report interpolation and RAW boundaries.

**Non-Goals:**

- Pixel-identical RAW development between `rawpy` and `CIRAWFilter`.
- Replacing Core Image's GPU cube renderer with a custom tetrahedral renderer.
- Treating the neutral base LUT as an untouched original.
- Adding third-party dependencies to LUTzy.

## Decisions

### Compare named pipeline stages

The comparison contract has three named outputs: decoded source, neutral base, and graded result. Source parity compares decoded standard sRGB pixels. Neutral and graded parity compare outputs after the same display-to-V-Log conversion and the same interpolation choice. This prevents a semantic mismatch from being “fixed” by changing correct RGB values.

Alternative: force LUTzy's Original to show the viewer's neutral LUT. Rejected because it would stop being the user's original image and would make display-input LUTs inconsistent.

### Use trilinear as the cross-application parity mode

LUTzy retains `CIColorCube` and its Metal-accelerated trilinear interpolation. Reference vectors are generated with `lutcraft`'s trilinear sampler. The viewer's tetrahedral mode remains useful, but its output is not compared to LUTzy as if the interpolation were identical.

Alternative: implement a custom tetrahedral GPU pipeline in LUTzy. Rejected because it adds substantial render, cache, and export risk for a small interpolation difference that the viewer can already switch off.

### Pin ordinary-photo conversion with full-pipeline vectors

`NeutralRender` owns the scalar inverse of the neutral tone render. `VLogInputAdapter` implements the same transform in a Core Image kernel. Golden fixtures include standard sRGB input, expected V-Log/V-Gamut codes, and expected neutral/representative-look outputs. Tests exercise the real Core Image kernel and cube path with explicit sRGB readback.

String substitutions in kernel source use non-overlapping placeholders or replace the longer token first. A scalar test alone is insufficient because a kernel can fail to compile while the CPU maths still passes.

### Keep the RAW boundary explicit

For RAW, both applications must remain internally consistent between preview and export, but cross-app results are described as decoder-dependent. Acceptance reports the decoder choice and does not apply standard-image pixel tolerances to RAW.

## Risks / Trade-offs

- **Golden vectors can accidentally validate a reimplementation rather than the reference.** → Generate them from the documented `lutcraft` forward render/cube data and record interpolation and encoding in the fixture header.
- **Embedded colour profiles can make a “same JPEG” comparison use different decoded values.** → Start with an explicit sRGB fixture; add profiled-image cases separately and require conversion into sRGB before parity comparison.
- **Exact inverse maths differs slightly from the viewer's current iterative inverse.** → Measure the difference, update the shared reference implementation or keep a stated tolerance; do not silently claim bit identity.
- **Core Image kernel compilation failures can degrade to an ungraded image.** → Test kernel construction directly and keep the pipeline fallback that skips the LUT instead of indexing it with the wrong values.

## Migration Plan

1. Preserve and validate the existing Neutral Render draft.
2. Add shared stage-labelled fixtures and full Core Image pipeline checks.
3. Correct any kernel or encoding mismatch found by those checks.
4. Run LUTzy build, `lutcheck`, and the viewer's Python tests.
5. Keep RAW marked decoder-dependent until both products intentionally adopt one decoder.

Rollback consists of reverting the adapter/inverse changes and their fixtures together; the pipeline fallback remains safe independently.

## Open Questions

- Whether `lut-viewer` should change its default interpolation to trilinear is a cross-repository product choice. Parity evidence will always state which interpolation was used.
