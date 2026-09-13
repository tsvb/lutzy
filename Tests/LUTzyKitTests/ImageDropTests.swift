import XCTest
import AppKit
import UniformTypeIdentifiers
@testable import LUTzyKit

/// Drops onto the preview canvas: how a pasteboard is classified, and what the view model does
/// with the result. The Photos case itself — a file promise — cannot be staged in a unit test,
/// because only a live drag session vends an `NSFilePromiseReceiver`; what is covered is everything
/// around it: the type list SwiftUI is given, the URL path the received files take, and the
/// housekeeping of the directory they land in.
@MainActor
final class ImageDropTests: TempDirectoryTestCase {

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func makePasteboard() -> NSPasteboard {
        let pb = NSPasteboard.withUniqueName()
        pb.clearContents()
        return pb
    }

    // MARK: - Classification

    func testAcceptedTypesCoverFilesImagesAndPromises() {
        XCTAssertTrue(ImageDrop.acceptedTypes.contains(.fileURL))
        XCTAssertTrue(ImageDrop.acceptedTypes.contains(.image))
        // The promise identifiers conform to nothing public, so they have to be listed themselves.
        let promise = NSFilePromiseReceiver.readableDraggedTypes.compactMap { UTType($0) }
        XCTAssertFalse(promise.isEmpty, "the SDK should declare at least one readable promise type")
        for type in promise {
            XCTAssertTrue(ImageDrop.acceptedTypes.contains(type), "missing \(type.identifier)")
        }
    }

    func testFileURLsAreReadAsURLs() throws {
        let a = try Fixtures.writeJPEG(width: 8, height: 8, orientation: 1, named: "a.jpg", in: tempDirectory)
        let b = try Fixtures.writeJPEG(width: 8, height: 8, orientation: 1, named: "b.jpg", in: tempDirectory)
        let pb = makePasteboard()
        pb.writeObjects([a as NSURL, b as NSURL])

        guard case .urls(let urls)? = ImageDrop.payload(from: pb) else {
            return XCTFail("expected a URL payload")
        }
        XCTAssertEqual(urls.map(\.lastPathComponent), ["a.jpg", "b.jpg"])
    }

    func testBitmapDataIsReadAsAnImage() {
        let pb = makePasteboard()
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        XCTAssertTrue(pb.writeObjects([image]))

        guard case .image(let data, let name)? = ImageDrop.payload(from: pb) else {
            return XCTFail("expected an image payload")
        }
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(name, "Dropped Image.tiff")
    }

    func testAWebURLIsNotAFile() {
        let pb = makePasteboard()
        pb.writeObjects([URL(string: "https://example.com/a.jpg")! as NSURL])
        XCTAssertNil(ImageDrop.payload(from: pb))
        XCTAssertFalse(ImageDrop.canAccept(pb))
    }

    func testAnEmptyPasteboardIsRejected() {
        XCTAssertNil(ImageDrop.payload(from: makePasteboard()))
    }

    // MARK: - Opening dropped URLs

    func testSeveralFilesBecomeACollectionWithTheFirstOpen() async throws {
        let a = try Fixtures.writeJPEG(width: 8, height: 8, orientation: 1, named: "a.jpg", in: tempDirectory)
        let b = try Fixtures.writeJPEG(width: 8, height: 8, orientation: 1, named: "b.jpg", in: tempDirectory)
        let notes = tempDirectory.appendingPathComponent("notes.txt")
        try "not an image".write(to: notes, atomically: true, encoding: .utf8)

        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.openDropped(urls: [a, notes, b])

        XCTAssertTrue(viewModel.collection.isActive)
        XCTAssertEqual(viewModel.collection.items.map(\.displayName), ["a", "b"], "unsupported files are skipped")
        XCTAssertNil(viewModel.collection.sourceFolderURL, "a dropped set is not a source folder")
        try await waitUntil("a.jpg to open") { viewModel.sourceName == "a.jpg" }
    }

    func testASingleFileReplacesTheCollection() async throws {
        let a = try Fixtures.writeJPEG(width: 8, height: 8, orientation: 1, named: "a.jpg", in: tempDirectory)
        let b = try Fixtures.writeJPEG(width: 8, height: 8, orientation: 1, named: "b.jpg", in: tempDirectory)
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.openDropped(urls: [a, b])
        XCTAssertTrue(viewModel.collection.isActive)

        viewModel.openDropped(urls: [b])
        XCTAssertFalse(viewModel.collection.isActive)
        try await waitUntil("b.jpg to open") { viewModel.sourceName == "b.jpg" }
    }

    func testASingleFolderBecomesTheSourceFolder() async throws {
        let folder = tempDirectory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try Fixtures.writeJPEG(width: 8, height: 8, orientation: 1, named: "a.jpg", in: folder)

        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.openDropped(urls: [folder])
        await viewModel.collection.scanCompletion()

        XCTAssertEqual(viewModel.collection.sourceFolderURL, folder)
        XCTAssertEqual(viewModel.collection.items.map(\.displayName), ["a"])
    }

    // MARK: - Promise landing directory

    func testEachDropGetsItsOwnDirectoryAndOlderOnesArePurged() throws {
        let first = try ImageDrop.makeDropDirectory()
        let second = try ImageDrop.makeDropDirectory()
        XCTAssertNotEqual(first, second)
        try "x".write(to: first.appendingPathComponent("IMG_0001.jpeg"), atomically: true, encoding: .utf8)

        ImageDrop.purgeDropDirectories(except: second)

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        ImageDrop.purgeDropDirectories(except: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
    }

    func testReceivingNothingReturnsNothing() async {
        let urls = await ImageDrop.receive([], into: tempDirectory)
        XCTAssertTrue(urls.isEmpty)
    }
}
