import AppKit

/// One render identity shared by every visual instance of a LUT card.
/// A LUT can occur in several discovery shelves, so view-local state alone is
/// not enough to prevent duplicate GPU requests.
struct LUTGalleryPreviewCacheKey: Hashable, Sendable {
    let lutID: LUTID
    let revision: Int
    let sampleID: String?
    let context: String
    let width: Int
    let height: Int
}

/// Main-actor isolation keeps AppKit images safe while coalescing concurrent
/// card requests. The last cancelled waiter cancels the shared render; a small
/// bounded completed cache lets the same LUT reappear in another shelf without
/// retaining the entire library at preview resolution.
@MainActor
final class LUTGalleryPreviewCache {
    /// `Task.Success` must be Sendable even when the task and every consumer
    /// are main-actor isolated. This box never leaves `LUTGalleryPreviewCache`;
    /// the unchecked conformance only bridges that compiler rule, while all
    /// NSImage creation and access remains on the main actor.
    private final class MainActorImage: @unchecked Sendable {
        let value: NSImage
        init(_ value: NSImage) { self.value = value }
    }

    private struct InFlight {
        let task: Task<MainActorImage?, Never>
        var waiters: Set<UUID>
    }

    private let countLimit: Int
    private var completed: [LUTGalleryPreviewCacheKey: NSImage] = [:]
    private var completionOrder: [LUTGalleryPreviewCacheKey] = []
    private var inFlight: [LUTGalleryPreviewCacheKey: InFlight] = [:]

    init(countLimit: Int = 96) {
        self.countLimit = max(countLimit, 1)
    }

    func image(
        for key: LUTGalleryPreviewCacheKey,
        render: @escaping @MainActor @Sendable () async -> NSImage?
    ) async -> NSImage? {
        if let image = completed[key] {
            touch(key)
            return image
        }

        let waiterID = UUID()
        let task: Task<MainActorImage?, Never>
        if var request = inFlight[key] {
            request.waiters.insert(waiterID)
            inFlight[key] = request
            task = request.task
        } else {
            task = Task { @MainActor in
                guard let image = await render() else { return nil }
                return MainActorImage(image)
            }
            inFlight[key] = InFlight(task: task, waiters: [waiterID])
        }

        return await withTaskCancellationHandler {
            let image = await task.value?.value
            finishWaiter(waiterID, for: key, image: image)
            return Task.isCancelled ? nil : image
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelWaiter(waiterID, for: key)
            }
        }
    }

    func removeAll() {
        inFlight.values.forEach { $0.task.cancel() }
        inFlight.removeAll()
        completed.removeAll()
        completionOrder.removeAll()
    }

    private func finishWaiter(
        _ waiterID: UUID,
        for key: LUTGalleryPreviewCacheKey,
        image: NSImage?
    ) {
        guard var request = inFlight[key], request.waiters.remove(waiterID) != nil else { return }
        guard request.waiters.isEmpty else {
            inFlight[key] = request
            return
        }

        inFlight[key] = nil
        if let image { insert(image, for: key) }
    }

    private func cancelWaiter(_ waiterID: UUID, for key: LUTGalleryPreviewCacheKey) {
        guard var request = inFlight[key], request.waiters.remove(waiterID) != nil else { return }
        if request.waiters.isEmpty {
            request.task.cancel()
            inFlight[key] = nil
        } else {
            inFlight[key] = request
        }
    }

    private func insert(_ image: NSImage, for key: LUTGalleryPreviewCacheKey) {
        completed[key] = image
        touch(key)
        while completionOrder.count > countLimit, let oldest = completionOrder.first {
            completionOrder.removeFirst()
            completed[oldest] = nil
        }
    }

    private func touch(_ key: LUTGalleryPreviewCacheKey) {
        completionOrder.removeAll { $0 == key }
        completionOrder.append(key)
    }
}
