## 1. Establish the comparison baseline

- [x] 1.1 Trace and name the decoded-source, neutral-base, and graded stages in both applications
- [x] 1.2 Measure neutral reconstruction, trilinear-versus-tetrahedral output, and the existing inverse-vector difference
- [x] 1.3 Record the interpolation and encoding metadata beside the shared golden fixtures

## 2. Harden the standard-image pipeline

- [x] 2.1 Validate and correct the Neutral Render CPU and Core Image kernel implementations, including kernel placeholder substitution
- [x] 2.2 Add full-pipeline trilinear vectors covering neutral and representative look output
- [x] 2.3 Exercise the actual Core Image adapter and cube path against those vectors
- [x] 2.4 Preserve and verify the safe no-LUT fallback when adaptation fails

## 3. Document boundaries and verify

- [x] 3.1 Document that Original and neutral base are different stages and that RAW output is decoder-dependent
- [x] 3.2 Run LUTzy debug/release builds, `lutcheck`, and the `lut-viewer` Python suite
- [x] 3.3 Validate the OpenSpec change and record residual trilinear parity (neutral ≤ 0.0013; Provia ≤ 0.0008)
