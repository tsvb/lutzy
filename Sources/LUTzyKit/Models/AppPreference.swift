import Foundation

/// The `UserDefaults` keys behind the Settings window (⌘,).
///
/// Three of these are *launch* defaults: `AppViewModel` and `ExportCoordinator` read them once in
/// `init`, because an `@Observable` class cannot host `@AppStorage` (the macro rejects other
/// property wrappers, and `@AppStorage` needs a view to invalidate anyway). The Settings copy says
/// so. `collapsedLUTCategories` is the exception — the sidebar reads it live through `@AppStorage`,
/// so "Expand All" in Settings takes effect on screen at once.
///
/// Not `PreferenceKey`, which is a SwiftUI protocol every view file would shadow.
enum AppPreference {
    /// Folder names collapsed in the LUT sidebar, newline-separated. (Was a `[String]`; a value in
    /// the old shape reads as the default, i.e. everything expanded, and is rewritten on first use.)
    static let collapsedLUTCategories = "lutzy.collapsedLUTCategories"
    /// Whether a new window starts in side-by-side comparison. Default `true`.
    static let defaultSideBySide = "lutzy.defaultSideBySide"
    /// Whether restoring the source folder at launch also shows the browser. Default `true`.
    static let showSourceBrowserOnRestore = "lutzy.showSourceBrowserOnRestore"
    /// `ExportFormat.rawValue` to start with. Default JPEG.
    static let defaultExportFormat = "lutzy.defaultExportFormat"
}

extension UserDefaults {
    /// `bool(forKey:)` returns `false` for an absent key, which is the wrong default for most
    /// preferences; this one distinguishes "unset" from "off".
    func bool(forKey key: String, default fallback: Bool) -> Bool {
        object(forKey: key) as? Bool ?? fallback
    }
}
