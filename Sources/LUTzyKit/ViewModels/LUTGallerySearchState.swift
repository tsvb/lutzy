import Combine
import Foundation

/// Keeps keystrokes local to the search field and only publishes a settled
/// query to the LUT grid. Rebuilding a gallery with thousands of cards on
/// every character makes the text field itself feel stuck; the draft text
/// still updates immediately, while result reconciliation is coalesced.
@MainActor
final class LUTGallerySearchState: ObservableObject {
    @Published private(set) var query = ""

    private let debounce: Duration
    private var pending: Task<Void, Never>?

    init(debounce: Duration = .milliseconds(140)) {
        self.debounce = debounce
    }

    func submit(_ draft: String) {
        pending?.cancel()

        guard draft.isEmpty == false else {
            query = ""
            return
        }

        pending = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: debounce)
            guard Task.isCancelled == false else { return }
            query = draft
        }
    }
}
