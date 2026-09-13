import SwiftUI

/// The one sheet for every update phase: checking, up to date, available, in progress, failed.
struct UpdateSheet: View {
    let coordinator: UpdateCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch coordinator.phase {
            case .none, .checking:
                header("Checking for updates…", detail: nil)
                ProgressView().controlSize(.small)
                buttons { Button("Cancel") { coordinator.dismiss() }.keyboardShortcut(.cancelAction) }

            case .upToDate:
                header("LUTzy is up to date", detail: versionLine)
                buttons { Button("OK") { coordinator.dismiss() }.keyboardShortcut(.defaultAction) }

            case .available(let release):
                header("\(release.title) is available", detail: versionLine)
                notes(release.notes)
                buttons {
                    Button("Skip This Version") { coordinator.skip(release) }
                    Spacer()
                    Button("Later") { coordinator.remindLater() }.keyboardShortcut(.cancelAction)
                    if coordinator.canInstallInPlace && release.diskImageURL != nil {
                        Button("Install and Relaunch") { coordinator.installAndRelaunch(release) }
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Open Release Page") { coordinator.openReleasePage(release) }
                            .keyboardShortcut(.defaultAction)
                    }
                }

            case .downloading(let release):
                header("Downloading \(release.title)…", detail: sizeLine(release))
                ProgressView().controlSize(.small)

            case .installing(let release):
                header("Installing \(release.title)…", detail: "LUTzy will relaunch in a moment.")
                ProgressView().controlSize(.small)

            case .failed(let message):
                header("The update didn't go through", detail: message)
                buttons { Button("OK") { coordinator.dismiss() }.keyboardShortcut(.defaultAction) }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var versionLine: String? {
        coordinator.currentVersion.map { "You have \($0)." }
    }

    private func sizeLine(_ release: Release) -> String? {
        release.diskImageSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
    }

    private func header(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            if let detail {
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    /// Release notes are GitHub Markdown. Inline syntax renders; block syntax (headings, lists)
    /// keeps its line breaks and reads as plain text, which is fine for a changelog.
    private func notes(_ markdown: String) -> some View {
        ScrollView {
            Text(attributed(markdown))
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 220)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    private func attributed(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }

    private func buttons<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack { content() }
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
