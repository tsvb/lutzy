import AppKit
import Foundation
@testable import LUTzyKit

@MainActor
func runDurableLibraryChecks() async -> Bool {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("lutcheck-library-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let catalogURL = root.appendingPathComponent("catalog.json")
        let catalog = LUTCatalog(fileURL: catalogURL)
        let cubeA = root.appendingPathComponent("A.cube")
        let cubeB = root.appendingPathComponent("B.cube")
        let cubeText = identityCube(size: 2)
        try cubeText.write(to: cubeA, atomically: true, encoding: .utf8)
        try cubeText.write(to: cubeB, atomically: true, encoding: .utf8)
        let first = try CubeLUT(url: cubeA)
        let second = try CubeLUT(url: cubeB)
        guard let firstID = catalog.adoptSavedLUT(first),
              let secondID = catalog.adoptSavedLUT(second),
              firstID != secondID,
              let collection = catalog.createCollection(named: "低飽和")
        else {
            print("durable LUT catalog -> FAIL")
            return false
        }
        catalog.setMembership(true, collectionID: collection.id, recordIDs: [firstID, secondID])
        catalog.addTag("soft", to: [firstID])
        catalog.setOrigin(.custom, for: [firstID])

        let relaunchedCatalog = LUTCatalog(fileURL: catalogURL)
        let catalogOK = relaunchedCatalog.members(of: collection.id) == Set([firstID, secondID])
            && relaunchedCatalog.record(for: firstID)?.typedTags == ["soft"]
            && relaunchedCatalog.record(for: firstID)?.origin == .custom
            && relaunchedCatalog.loadLUT(for: firstID)?.lutID == firstID
        print("durable LUT catalog -> \(catalogOK ? "PASS" : "FAIL")")

        let recoveredScope = root.appendingPathComponent("External Scope", isDirectory: true)
        try FileManager.default.createDirectory(at: recoveredScope, withIntermediateDirectories: true)
        let recoveredURL = recoveredScope.appendingPathComponent("Recovered.cube")
        let transientID = LUTID(raw: "derived://lutcheck/interrupted")
        let scopeBookmark = try? recoveredScope.bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil
        )
        let markerOK = scopeBookmark != nil && relaunchedCatalog.beginSaveRecovery(
            for: recoveredURL, replacing: transientID,
            expectedFingerprint: first.contentHash, bookmark: scopeBookmark,
            bookmarkRelativePath: recoveredURL.lastPathComponent
        )
        try cubeText.write(to: recoveredURL, atomically: true, encoding: .utf8)
        let afterInterruptedSave = LUTCatalog(fileURL: catalogURL)
        let recoveredID = afterInterruptedSave.recordID(for: recoveredURL)
        let recoveryOK = markerOK
            && recoveredID?.isRecord == true
            && afterInterruptedSave.loadLUT(for: transientID)?.url.standardizedFileURL
                == recoveredURL.standardizedFileURL
            && afterInterruptedSave.loadLUT(for: transientID)?.lutID == recoveredID
        print("derived save recovery -> \(recoveryOK ? "PASS" : "FAIL")")

        let recoveryProjectRoot = root.appendingPathComponent("Recovery Projects", isDirectory: true)
        let recoveryProjects = ProjectStore(root: recoveryProjectRoot)
        _ = recoveryProjects.create(named: "Interrupted Save")
        var recoverySession = Project.Session()
        recoverySession.selectedLUT = transientID.raw
        recoveryProjects.updateSession(recoverySession)
        let recoveryLibrary = LUTLibrary(catalog: afterInterruptedSave)
        recoveryLibrary.setFolder(root)
        await recoveryLibrary.scanCompletion()
        let recoveryMedia = MediaLibrary(
            root: root.appendingPathComponent("Recovery Media", isDirectory: true),
            manifestURL: root.appendingPathComponent("recovery-media.json")
        )
        let recoveryViewModel = AppViewModel(
            projects: recoveryProjects,
            tags: LUTTagStore(fileURL: root.appendingPathComponent("recovery-tags.json")),
            media: recoveryMedia,
            library: recoveryLibrary
        )
        let recoveryDeadline = Date().addingTimeInterval(3)
        while recoveryProjects.current?.session.selectedLUT != recoveredID?.raw,
              Date() < recoveryDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let recoveredSessionOK = recoveryViewModel.document.lut.lutID == recoveredID
            && recoveryProjects.current?.session.selectedLUT == recoveredID?.raw
            && ProjectStore(root: recoveryProjectRoot).current?.session.selectedLUT == recoveredID?.raw
        print("derived session adoption -> \(recoveredSessionOK ? "PASS" : "FAIL")")

        let brandShelves = recoveryViewModel.libraryDiscoveryShelves(for: .brand)
        let tagShelves = recoveryViewModel.libraryDiscoveryShelves(for: .tag)
        let collectionShelves = recoveryViewModel.libraryDiscoveryShelves(for: .collection)
        let brandOK = brandShelves.first(where: { $0.title == "Custom" })?.luts.map(\.lutID).contains(firstID) == true
            && brandShelves.first(where: { $0.title == "Unknown" })?.luts.map(\.lutID).contains(secondID) == true
        let tagOK = tagShelves.first(where: { $0.title == "soft" })?.luts.map(\.lutID) == [firstID]
            && tagShelves.contains(where: { $0.title.hasPrefix("input:") }) == false
        let collectionOK = Set(
            collectionShelves.first(where: { $0.title == "低飽和" })?.luts.map(\.lutID) ?? []
        ) == Set([firstID, secondID])
        recoveryViewModel.setLUTSource(.collection(collection.id), for: .library)
        let scopedCount = recoveryViewModel.libraryDiscoveryShelves(for: .brand)
            .reduce(0) { $0 + $1.luts.count }
        let discoveryOK = brandOK && tagOK && collectionOK && scopedCount == 2
        recoveryViewModel.setLUTSource(.all, for: .library)
        print("LUT discovery Brand/Tag/Collection shelves and source scope -> \(discoveryOK ? "PASS" : "FAIL")")

        let survivingShelf = LUTLibraryShelf(
            id: "tag:soft", title: "soft", luts: [first]
        )
        let focusRecoveryOK = LUTLibraryFocusTarget.homeCard(
            shelfID: survivingShelf.id, lutID: secondID
        ).resolved(in: [survivingShelf]) == .shelfHeading(survivingShelf.id)
            && LUTLibraryFocusTarget.gridCard(
                shelfID: survivingShelf.id, lutID: secondID
            ).resolved(in: [survivingShelf]) == .gridBack(survivingShelf.id)
            && LUTLibraryFocusTarget.gridCard(
                shelfID: survivingShelf.id, lutID: secondID
            ).resolved(in: []) == .groupingControl
        print("LUT discovery focus fallback after card/shelf removal -> \(focusRecoveryOK ? "PASS" : "FAIL")")

        let previewCache = LUTGalleryPreviewCache(countLimit: 4)
        let previewKey = LUTGalleryPreviewCacheKey(
            lutID: firstID, revision: 1, sampleID: "outdoor",
            context: "library", width: 640, height: 400
        )
        var previewRenderCount = 0
        let firstPreview = Task { @MainActor in
            let image = await previewCache.image(for: previewKey) {
                previewRenderCount += 1
                try? await Task.sleep(for: .milliseconds(40))
                return NSImage(size: NSSize(width: 8, height: 8))
            }
            return image != nil
        }
        let duplicatePreview = Task { @MainActor in
            let image = await previewCache.image(for: previewKey) {
                previewRenderCount += 1
                return NSImage(size: NSSize(width: 8, height: 8))
            }
            return image != nil
        }
        let previewsRendered = await (firstPreview.value, duplicatePreview.value)
        let cachedPreview = await previewCache.image(for: previewKey) {
            previewRenderCount += 1
            return NSImage(size: NSSize(width: 8, height: 8))
        }

        let cancelledKey = LUTGalleryPreviewCacheKey(
            lutID: secondID, revision: 1, sampleID: "outdoor",
            context: "library", width: 640, height: 400
        )
        var cancellationObserved = false
        let cancelledPreview = Task { @MainActor in
            let image = await previewCache.image(for: cancelledKey) {
                do {
                    try await Task.sleep(for: .seconds(2))
                    return NSImage(size: NSSize(width: 8, height: 8))
                } catch {
                    cancellationObserved = true
                    return nil
                }
            }
            return image != nil
        }
        await Task.yield()
        cancelledPreview.cancel()
        _ = await cancelledPreview.value
        let previewCacheOK = previewsRendered.0
            && previewsRendered.1
            && cachedPreview != nil
            && previewRenderCount == 1
            && cancellationObserved
        print("shared LUT preview cache coalescing and cancellation -> \(previewCacheOK ? "PASS" : "FAIL")")

        let legacyProjectRoot = root.appendingPathComponent("Legacy Projects", isDirectory: true)
        let legacyProjects = ProjectStore(root: legacyProjectRoot)
        let legacyProject = legacyProjects.create(named: "Legacy")
        let legacyImage = legacyProjects.imagesFolder(for: legacyProject)
            .appendingPathComponent("legacy.png")
        let legacyImageOK = writeJPEG(description: nil, to: legacyImage, colourful: true)
        var legacySession = Project.Session()
        legacySession.selectedLUT = cubeA.path
        legacySession.cellLUTs = [cubeA.path]
        legacySession.imageName = legacyImage.lastPathComponent
        legacyProjects.updateSession(legacySession)
        let legacyLibrary = LUTLibrary(catalog: afterInterruptedSave)
        legacyLibrary.setFolder(root)
        await legacyLibrary.scanCompletion()
        let legacyMedia = MediaLibrary(
            root: root.appendingPathComponent("Legacy Media", isDirectory: true),
            manifestURL: root.appendingPathComponent("legacy-media.json")
        )
        let legacyViewModel = AppViewModel(
            projects: legacyProjects,
            tags: LUTTagStore(fileURL: root.appendingPathComponent("legacy-tags.json")),
            media: legacyMedia,
            library: legacyLibrary
        )
        let legacyDeadline = Date().addingTimeInterval(3)
        while (legacyProjects.current?.session.selectedLUT != firstID.raw
                || legacyProjects.current?.session.cellLUTs != [firstID.raw]
                || legacyProjects.current?.session.mediaRecordID == nil),
              Date() < legacyDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let relaunchedLegacySession = ProjectStore(root: legacyProjectRoot).current?.session
        let legacyMigrationOK = legacyImageOK
            && legacyViewModel.document.lut.lutID == firstID
            && relaunchedLegacySession?.selectedLUT == firstID.raw
            && relaunchedLegacySession?.cellLUTs == [firstID.raw]
            && relaunchedLegacySession?.mediaRecordID != nil
        print("legacy session migration -> \(legacyMigrationOK ? "PASS" : "FAIL")")
        if legacyMigrationOK == false {
            print("  image \(legacyImageOK), document \(legacyViewModel.document.lut.lutID?.raw ?? "nil"), selected \(relaunchedLegacySession?.selectedLUT ?? "nil"), cells \(relaunchedLegacySession?.cellLUTs ?? []), media \(relaunchedLegacySession?.mediaRecordID ?? "nil")")
            print("  restoring \(legacyViewModel.restoreDepth), scanned \(legacyLibrary.allLUTs.map { "\($0.id)=\($0.lutID.raw)" })")
        }

        let importFolder = root.appendingPathComponent("Shoot/Day 1", isDirectory: true)
        try FileManager.default.createDirectory(at: importFolder, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4e, 0x47, 1]).write(
            to: importFolder.appendingPathComponent("frame.png")
        )
        try Data([0, 0, 0, 20, 0x66, 0x74, 0x79, 0x70]).write(
            to: importFolder.appendingPathComponent("clip.mov")
        )
        let mediaRoot = root.appendingPathComponent("Media", isDirectory: true)
        let mediaURL = root.appendingPathComponent("media.json")
        let media = MediaLibrary(root: mediaRoot, manifestURL: mediaURL)
        let importResult = await media.importMedia(from: [root.appendingPathComponent("Shoot")])
        let mediaIDs = Set(media.records.map(\.id))
        let relaunchedMedia = MediaLibrary(root: mediaRoot, manifestURL: mediaURL)
        let mediaOK = importResult.imported == 2
            && media.records.contains { $0.kind == .image }
            && media.records.contains { $0.kind == .video }
            && Set(relaunchedMedia.records.map(\.id)) == mediaIDs
            && relaunchedMedia.records.contains { $0.logicalPath == "Shoot/Day 1/frame.png" }
        print("durable Media Library -> \(mediaOK ? "PASS" : "FAIL")")
        return catalogOK && recoveryOK && recoveredSessionOK && discoveryOK && focusRecoveryOK
            && previewCacheOK && legacyMigrationOK && mediaOK
    } catch {
        print("durable library checks -> FAIL (\(error))")
        return false
    }
}

private func identityCube(size: Int) -> String {
    var lines = ["TITLE \"identity\"", "LUT_3D_SIZE \(size)"]
    let denominator = Float(size - 1)
    for b in 0..<size {
        for g in 0..<size {
            for r in 0..<size {
                lines.append(String(
                    format: "%.6f %.6f %.6f",
                    Float(r) / denominator, Float(g) / denominator, Float(b) / denominator
                ))
            }
        }
    }
    return lines.joined(separator: "\n") + "\n"
}
