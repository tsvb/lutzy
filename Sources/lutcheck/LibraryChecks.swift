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
        return catalogOK && mediaOK
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
