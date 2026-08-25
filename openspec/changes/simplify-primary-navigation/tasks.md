## 1. Primary mode model

- [x] 1.1 Reduce `AppSection` and the primary sidebar to Viewer, LUT Manager, and LUT Editor
- [x] 1.2 Decode the removed `images` section as Viewer and keep existing manager session compatibility
- [x] 1.3 Remove project controls from primary navigation and create an implicit image workspace when needed

## 2. Feature ownership

- [x] 2.1 Move All LUTs, Starred, folders, and LUT import into the LUT library column
- [x] 2.2 Route List/Gallery image browsing through Viewer and return to preview when an image opens
- [x] 2.3 Remove project terminology from reachable image-management copy

## 3. Verification

- [x] 3.1 Verify all three primary modes, stable LUT Manager selection across scope changes, and Viewer image browsing in the running app
- [x] 3.2 Run focused CLI checks, debug and release builds, and `lutcheck`
- [x] 3.3 Validate both affected OpenSpec changes and verify conflict-free integration with `main`
