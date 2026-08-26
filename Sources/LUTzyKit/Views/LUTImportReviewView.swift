import SwiftUI

/// A read-only hand-off after local import. It answers "do I already own
/// something that behaves like this?" without turning a recommendation into
/// an automatic rename, move, Tag, or Collection mutation.
struct LUTImportReviewView: View {
    let review: LUTImportReview
    let onInspect: (LUTID) -> Void
    let onDismiss: () -> Void

    @State private var selection: LUTID?

    init(
        review: LUTImportReview,
        onInspect: @escaping (LUTID) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.review = review
        self.onInspect = onInspect
        self.onDismiss = onDismiss
        _selection = State(initialValue: review.recommendations.first?.id)
    }

    private var selected: LUTImportRecommendation? {
        review.recommendations.first { $0.id == selection } ?? review.recommendations.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                importedList
                    .frame(minWidth: 230, idealWidth: 270, maxWidth: 330)
                detail
                    .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 500, idealHeight: 580)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text("Import Review")
                    .font(.title3.weight(.semibold))
                Text("Similarity is measured from colour behaviour, not filenames or folders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(importSummary)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var importedList: some View {
        List(review.recommendations, selection: $selection) { item in
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(item.inputSpace == .vlog ? "V-Log" : "Display")
                    Text("·")
                    Text(item.matches.isEmpty ? "No clear match" : "(item.matches.count) similar")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
            .tag(item.id)
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Imported LUTs")
    }

    @ViewBuilder
    private var detail: some View {
        if let selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(selected.name)
                            .font(.title2.weight(.semibold))
                        Text(selected.inputSpace == .vlog ? "V-Log input" : "Display input")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if selected.tags.isEmpty == false {
                        FlowLayout(spacing: 5, lineSpacing: 5) {
                            ForEach(selected.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.08), in: Capsule())
                            }
                        }
                    }

                    Divider()
                    Text("Similar LUTs already in your Library")
                        .font(.headline)

                    if selected.matches.isEmpty {
                        ContentUnavailableView {
                            Label("No clear match", systemImage: "checkmark.seal")
                        } description: {
                            Text("Nothing in the same input space passed the confidence threshold. The nearest item was not promoted into a recommendation.")
                        }
                        .frame(maxWidth: .infinity, minHeight: 210)
                    } else {
                        ForEach(selected.matches) { match in
                            matchRow(match)
                        }
                    }
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView("Nothing imported", systemImage: "cube.transparent")
        }
    }

    private func matchRow(_ match: LUTImportMatch) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(Int((match.similarity * 100).rounded()))%")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 54, alignment: .trailing)
                .accessibilityLabel("\(Int((match.similarity * 100).rounded())) percent similar")

            VStack(alignment: .leading, spacing: 6) {
                Text(match.name)
                    .font(.subheadline.weight(.semibold))
                if match.sharedTraits.isEmpty == false {
                    Text("Shared: \(match.sharedTraits.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button("Inspect") { onInspect(match.id) }
                .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }

    private var footer: some View {
        HStack {
            Text("Compared with \(review.comparedAgainst) existing LUT\(review.comparedAgainst == 1 ? "" : "s"). No metadata was changed.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done", action: onDismiss)
                .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }

    private var importSummary: String {
        var parts = ["\(review.imported) imported"]
        if review.duplicates > 0 { parts.append("\(review.duplicates) duplicate") }
        if review.failed > 0 { parts.append("\(review.failed) failed") }
        return parts.joined(separator: " · ")
    }
}
