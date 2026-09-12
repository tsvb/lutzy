import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Modal sheet for deriving a .cube LUT from a (RAW, JPG) pair.
/// Scratch-mode: the derived LUT lives in `coordinator.derivedLUT` until the
/// user clicks Save. Observes `DeriveCoordinator` directly rather than the
/// whole app view model — this sheet touches nothing else.
struct RecipeExtractorSheet: View {
    let coordinator: DeriveCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var rawURL: URL?
    @State private var jpgURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            VStack(spacing: 8) {
                filePickerRow(
                    label: "RAW",
                    url: rawURL,
                    placeholder: "Choose RAW/DNG…",
                    onPick: pickRAW
                )
                filePickerRow(
                    label: "JPG",
                    url: jpgURL,
                    placeholder: "Choose JPG…",
                    onPick: pickJPG
                )
            }

            if coordinator.isDeriving {
                progressBlock
            }

            if let report = coordinator.report, !coordinator.isDeriving {
                Divider()
                RecipeReportView(report: report)
            }

            Spacer(minLength: 0)

            footerButtons
        }
        .padding(20)
        .frame(width: 540)
        .frame(minHeight: coordinator.report == nil ? 280 : 540)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Derive LUT from JPG")
                .font(.title2.bold())
            Text("Extract a .cube LUT from a (RAW, JPG) pair by comparing pixel correspondences. The derived LUT lives as a preview until you save it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - File picker rows

    private func filePickerRow(
        label: String,
        url: URL?,
        placeholder: String,
        onPick: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)

            HStack {
                Image(systemName: url == nil ? "doc" : "doc.fill")
                    .foregroundStyle(url == nil ? .secondary : .primary)
                Text(url?.lastPathComponent ?? placeholder)
                    .foregroundStyle(url == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            Button("Choose…") { onPick() }
                .buttonStyle(.bordered)
        }
    }

    // MARK: - Progress block

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: coordinator.progress)
            Text(coordinator.stage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Footer buttons

    private var footerButtons: some View {
        HStack {
            Button("Close") {
                coordinator.dismiss()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if coordinator.derivedLUT != nil && !coordinator.isDeriving {
                Button("Save to LUT Folder…") {
                    coordinator.saveDialog()
                }
            }

            Button("Derive") {
                if let r = rawURL, let j = jpgURL {
                    coordinator.derive(rawURL: r, jpgURL: j)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(rawURL == nil || jpgURL == nil || coordinator.isDeriving)
        }
    }

    // MARK: - File pickers

    private func pickRAW() {
        let panel = NSOpenPanel()
        panel.title = "Select RAW or DNG"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        // RAW + DNG types — match what ImageDecoder knows how to load
        var types: [UTType] = [.rawImage]
        if let dng = UTType(filenameExtension: "dng") { types.append(dng) }
        for ext in ["cr2", "cr3", "nef", "arw", "orf", "raf", "rw2", "pef", "srw"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        panel.allowedContentTypes = types
        if panel.runModal() == .OK, let url = panel.url {
            rawURL = url
        }
    }

    private func pickJPG() {
        let panel = NSOpenPanel()
        panel.title = "Select JPG"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.jpeg]
        if panel.runModal() == .OK, let url = panel.url {
            jpgURL = url
        }
    }
}
