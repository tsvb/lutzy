import SwiftUI

/// The Settings window (⌘,). Reached from the executable through `ContentView.settings`, so the
/// kit keeps its two public types.
struct SettingsView: View {
    @AppStorage(AppPreference.defaultSideBySide) private var defaultSideBySide = true
    @AppStorage(AppPreference.showSourceBrowserOnRestore) private var showSourceBrowserOnRestore = true
    @AppStorage(AppPreference.defaultExportFormat) private var defaultExportFormat = ExportFormat.jpeg.rawValue
    @AppStorage(AppPreference.collapsedLUTCategories) private var collapsedLUTCategories = ""
    @AppStorage(AppPreference.automaticUpdateChecks) private var automaticUpdateChecks = true

    var body: some View {
        Form {
            Section {
                Toggle("Start in side-by-side view", isOn: $defaultSideBySide)
                Toggle("Show the source browser when a folder is restored", isOn: $showSourceBrowserOnRestore)
                Picker("Export format", selection: $defaultExportFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.rawValue).tag(format.rawValue)
                    }
                }
            } header: {
                Text("At launch")
            } footer: {
                Text("Applied the next time LUTzy opens. The toolbar changes the current window.")
            }

            Section("LUT library") {
                LabeledContent("Folder") {
                    HStack(spacing: 8) {
                        if let name = LUTLibrary.currentFolderName {
                            Text(name)
                                .foregroundStyle(.secondary)
                        }
                        Button("Choose…") {
                            NotificationCenter.default.post(name: .chooseLUTFolder, object: nil)
                        }
                    }
                }
                LabeledContent("Collapsed folders") {
                    Button("Expand All") { collapsedLUTCategories = "" }
                        .disabled(collapsedLUTCategories.isEmpty)
                }
            }

            Section {
                Toggle("Check for updates automatically", isOn: $automaticUpdateChecks)
                LabeledContent("Version") {
                    HStack(spacing: 8) {
                        Text(AppVersion.current?.description ?? "development build")
                            .foregroundStyle(.secondary)
                        Button("Check Now") {
                            NotificationCenter.default.post(name: .checkForUpdates, object: nil)
                        }
                    }
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Once a day, LUTzy looks at its GitHub releases. An update is installed only after its signature is verified against this copy.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}

public extension ContentView {
    /// The body of the app's `Settings` scene.
    static var settings: some View { SettingsView() }
}
