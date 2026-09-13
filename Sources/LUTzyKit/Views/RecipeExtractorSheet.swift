import SwiftUI
import UniformTypeIdentifiers

/// Modal sheet for deriving a .cube LUT from a (RAW, JPEG) pair.
/// Scratch-mode: the derived LUT lives in `coordinator.derivedLUT` until the
/// user clicks Save. Observes `DeriveCoordinator` directly rather than the
/// whole app view model — this sheet touches nothing else.
struct RecipeExtractorSheet: View {
    let coordinator: DeriveCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var rawURL: URL?
    @State private var jpgURL: URL?
    @State private var name: String = ""

    /// Which slot the open file importer is filling. Non-nil presents it.
    @State private var importTarget: ImportTarget?

    private enum ImportTarget: Identifiable {
        case raw, jpg
        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)

            Form {
                Section {
                    fileRow(
                        label: "RAW",
                        url: $rawURL,
                        target: .raw,
                        droppableExtensions: ["raw", "dng"]
                    )
                    fileRow(
                        label: "JPEG",
                        url: $jpgURL,
                        target: .jpg,
                        droppableExtensions: ["jpg", "jpeg"]
                    )
                    LabeledContent("Name") {
                        TextField("", text: $name)
                    }
                }

                if coordinator.isDeriving {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: coordinator.progress)
                            Text(coordinator.stage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let report = coordinator.report, !coordinator.isDeriving {
                    Section {
                        RecipeReportView(report: report)
                    } header: {
                        HStack {
                            Text("Result")
                            Spacer()
                            Button("Derive again") {
                                if let r = rawURL, let j = jpgURL {
                                    coordinator.derive(rawURL: r, jpgURL: j)
                                }
                            }
                            .buttonStyle(.link)
                            .disabled(coordinator.isDeriving)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            footerButtons
                .padding(20)
        }
        .frame(width: 560)
        .frame(minHeight: coordinator.report == nil ? 260 : 540, maxHeight: 640)
        .onChange(of: rawURL) { _, newValue in
            guard name.isEmpty, let raw = newValue else { return }
            name = raw.deletingPathExtension().lastPathComponent + " Look"
        }
        .fileImporter(
            isPresented: Binding(
                get: { importTarget != nil },
                set: { if !$0 { importTarget = nil } }
            ),
            allowedContentTypes: importTarget == .raw ? Self.rawTypes : [.jpeg],
            allowsMultipleSelection: false
        ) { result in
            guard let target = importTarget, case .success(let urls) = result, let url = urls.first else {
                return
            }
            // Picked URLs are security-scoped. Nothing here is sandboxed today, so this is a no-op
            // that becomes load-bearing the day an app target applies `LUTzy.entitlements`.
            _ = url.startAccessingSecurityScopedResource()
            switch target {
            case .raw:
                rawURL?.stopAccessingSecurityScopedResource()
                rawURL = url
            case .jpg:
                jpgURL?.stopAccessingSecurityScopedResource()
                jpgURL = url
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Derive LUT from RAW and JPEG")
                .font(.headline)
            Text("LUTzy compares your JPEG to a neutral render of the RAW and saves the difference as a .cube LUT. Both files must be the same frame.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - File rows

    private func fileRow(
        label: String,
        url: Binding<URL?>,
        target: ImportTarget,
        droppableExtensions: Set<String>
    ) -> some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                Image(systemName: "doc")
                    .foregroundStyle(url.wrappedValue == nil ? .tertiary : .secondary)
                Text(url.wrappedValue?.lastPathComponent ?? "Choose a file or drop one here")
                    .foregroundStyle(url.wrappedValue == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button("Choose…") { importTarget = target }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .dropDestination(for: URL.self) { items, _ in
            guard let dropped = items.first,
                  droppableExtensions.contains(dropped.pathExtension.lowercased()) else {
                return false
            }
            _ = dropped.startAccessingSecurityScopedResource()
            url.wrappedValue?.stopAccessingSecurityScopedResource()
            url.wrappedValue = dropped
            return true
        }
    }

    // MARK: - Footer buttons

    private var footerButtons: some View {
        HStack {
            Spacer()

            if coordinator.derivedLUT != nil {
                Button("Close") {
                    coordinator.dismiss()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Button("Save to LUT Folder…") {
                    coordinator.saveDialog(suggestedName: name.isEmpty ? nil : name)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel") {
                    coordinator.dismiss()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

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
    }

    // MARK: - File types

    /// RAW + DNG types — match what ImageDecoder knows how to load.
    private static var rawTypes: [UTType] {
        var types: [UTType] = [.rawImage]
        if let dng = UTType(filenameExtension: "dng") { types.append(dng) }
        for ext in ["cr2", "cr3", "nef", "arw", "orf", "raf", "rw2", "pef", "srw"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }
}
