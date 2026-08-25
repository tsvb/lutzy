## 1. Presentation and selection model

- [x] 1.1 Add the persisted List/Gallery presentation value with List as the default
- [x] 1.2 Extract and test Finder-like single, Command-toggle, and Shift-range selection logic

## 2. Gallery interface

- [x] 2.1 Add the accessible List/Gallery segmented control to the image manager
- [x] 2.2 Build the adaptive lazy thumbnail gallery with filename, folder, placeholder, and selected states
- [x] 2.3 Wire double-click, context menu, Open, Export Selected, and Remove to the shared selection

## 3. Verification

- [x] 3.1 Verify switching presentations preserves selection and action targets
- [x] 3.2 Run focused CLI checks, debug/release builds, and `lutcheck`; keep XCTest coverage for a full Xcode toolchain
- [x] 3.3 Validate the OpenSpec change

## 4. Navigation ownership

- [x] 4.1 Rename the sidebar destination to LUT Manager and place Images inside Viewer
- [x] 4.2 Remove the Images tab and image-management controls from LUT Manager
- [x] 4.3 Verify saved-section compatibility, navigation behaviour, build, and OpenSpec validation
