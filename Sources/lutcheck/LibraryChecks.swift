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
        let lazyFileTableOK = first.retainsTableData == false
            && first.tableFloats.count == 2 * 2 * 2 * 4
            && first.retainsTableData == false
        let replacedURL = root.appendingPathComponent("Replaced.cube")
        try cubeText.write(to: replacedURL, atomically: true, encoding: .utf8)
        let replacedAfterScan = try CubeLUT(url: replacedURL)
        let replacedHash = replacedAfterScan.contentHash
        let replacementText = cubeText.replacingOccurrences(
            of: "0.000000 0.000000 0.000000", with: "0.250000 0.000000 0.000000"
        )
        try replacementText.write(to: replacedURL, atomically: true, encoding: .utf8)
        let lazyIdentityOK = replacedAfterScan.contentHash == replacedHash
            && replacedAfterScan.materialized() == nil
            && LUTProfiler.measureIfAvailable(replacedAfterScan) == nil
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
        catalog.setStarred(true, for: [firstID])
        catalog.removeTag("persisted-auto", from: [firstID], hidingMeasuredFor: [firstID])

        let relaunchedCatalog = LUTCatalog(fileURL: catalogURL)
        let eagerlyLoadedOutsideRoot = relaunchedCatalog.loadLUT(for: firstID)
        let catalogOK = relaunchedCatalog.members(of: collection.id) == Set([firstID, secondID])
            && relaunchedCatalog.record(for: firstID)?.typedTags == ["soft"]
            && relaunchedCatalog.record(for: firstID)?.origin == .custom
            && relaunchedCatalog.record(for: firstID)?.isStarred == true
            && relaunchedCatalog.excludedMeasuredTags(for: firstID) == ["persisted-auto"]
            && eagerlyLoadedOutsideRoot?.lutID == firstID
            && eagerlyLoadedOutsideRoot?.retainsTableData == true
        print("durable LUT catalog -> \(catalogOK ? "PASS" : "FAIL")")

        relaunchedCatalog.removeTag(
            "mixed-auto", from: [firstID, secondID], hidingMeasuredFor: [firstID]
        )
        let mixedSelectionTagOK = relaunchedCatalog.excludedMeasuredTags(for: firstID)
                == ["mixed-auto", "persisted-auto"]
            && relaunchedCatalog.excludedMeasuredTags(for: secondID).isEmpty
            && (relaunchedCatalog.record(for: firstID)?.typedTags.contains("mixed-auto") ?? true) == false
            && (relaunchedCatalog.record(for: secondID)?.typedTags.contains("mixed-auto") ?? true) == false
        relaunchedCatalog.addTag("mixed-auto", to: [firstID, secondID])
        relaunchedCatalog.removeTag("mixed-auto", from: [firstID, secondID])
        print("Manager mixed Tag batch-remove does not add to absent LUTs -> \(mixedSelectionTagOK ? "PASS" : "FAIL")")

        let metadataTagStore = LUTTagStore(fileURL: root.appendingPathComponent("metadata-tags.json"))
        let durableFirst = first.withRecordID(firstID)
        metadataTagStore.indexNow([durableFirst])
        let measuredTag = metadataTagStore.measuredTags(for: durableFirst)
            .first { $0.hasPrefix("input:") == false }
        let metadataLibrary = LUTLibrary(catalog: relaunchedCatalog)
        let metadataViewModel = AppViewModel(
            projects: ProjectStore(root: root.appendingPathComponent("Metadata Projects")),
            tags: metadataTagStore,
            media: MediaLibrary(
                root: root.appendingPathComponent("Metadata Media"),
                manifestURL: root.appendingPathComponent("metadata-media.json")
            ),
            library: metadataLibrary
        )
        var visibleTagEditingOK = false
        if let measuredTag {
            metadataViewModel.removeTag(measuredTag, from: durableFirst)
            let removed = metadataViewModel.allTags(for: durableFirst).contains(measuredTag) == false
            metadataViewModel.addTag(measuredTag, to: [durableFirst])
            visibleTagEditingOK = removed
                && metadataViewModel.allTags(for: durableFirst).filter { $0 == measuredTag }.count == 1
                && relaunchedCatalog.typedTags(for: durableFirst) == ["soft", measuredTag].sorted()
                && relaunchedCatalog.excludedMeasuredTags(for: durableFirst) == ["persisted-auto"]
        }
        print("Manager visible measured-Tag remove and restore -> \(visibleTagEditingOK ? "PASS" : "FAIL")")

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

        // Manager exposes the dedicated persisted Brand namespace as a table column.
        // Unknown and Custom remain explicit values; a vendor uses its actual authored name.
        let managerBrandDefaultsOK = recoveryViewModel.managerBrandLabel(for: durableFirst) == "Custom"
            && recoveryViewModel.managerBrandLabel(for: second.withRecordID(secondID)) == "Unknown"
        recoveryViewModel.catalog.setOrigin(.vendor("Panasonic"), for: [firstID])
        let managerVendorBrandOK = recoveryViewModel.managerBrandLabel(for: durableFirst) == "Panasonic"
        recoveryViewModel.catalog.setOrigin(.custom, for: [firstID])
        let managerBrandColumnOK = managerBrandDefaultsOK && managerVendorBrandOK
        print("Manager Brand column uses persisted Brand -> \(managerBrandColumnOK ? "PASS" : "FAIL")")

        // A repository sidecar joins by immutable content fingerprint, seeds
        // record metadata once, and then gets out of the user's way.
        let curatedSource = root.appendingPathComponent("Curated Source", isDirectory: true)
        try FileManager.default.createDirectory(at: curatedSource, withIntermediateDirectories: true)
        let curatedCubeURL = curatedSource.appendingPathComponent("look.cube")
        try cubeText.write(to: curatedCubeURL, atomically: true, encoding: .utf8)
        let curatedCube = try CubeLUT(url: curatedCubeURL)
        let manifestURL = curatedSource.appendingPathComponent(CuratedLUTManifest.fileName)
        let manifestJSON = """
        {
          "version": 1,
          "sources": {
            "codex": {
              "label": "Codex",
              "description": "Codex 產生；測試用 V-Log LUT。",
              "reference": null,
              "license": "project-owned"
            }
          },
          "entries": [
            {
              "relativePath": "look.cube",
              "sha256": "\(curatedCube.contentHash.uppercased())",
              "brand": "Fujifilm",
              "inputProfile": "Panasonic V-Log",
              "tags": ["相機風格", "完成色", "input:vlog"],
              "sourceID": "codex",
              "description": null
            }
          ],
          "duplicates": [],
          "unsupported": []
        }
        """
        try manifestJSON.write(to: manifestURL, atomically: true, encoding: .utf8)
        let manifest = try CuratedLUTManifest.load(from: manifestURL)
        let manifestCatalogURL = root.appendingPathComponent("manifest-catalog.json")
        let manifestCatalog = LUTCatalog(fileURL: manifestCatalogURL)
        guard let curatedID = manifestCatalog.adoptSavedLUT(curatedCube) else {
            print("curated LUT manifest metadata -> FAIL")
            return false
        }
        manifestCatalog.seedCuratedMetadata(
            manifest.metadataByFingerprint,
            for: [curatedCube.withRecordID(curatedID)]
        )
        let firstSeedOK = manifestCatalog.record(for: curatedID)?.origin == .vendor("Fujifilm")
            && manifestCatalog.record(for: curatedID)?.inputProfile == "Panasonic V-Log"
            && manifestCatalog.record(for: curatedID)?.typedTags == ["完成色", "相機風格"]
            && manifestCatalog.description(for: curatedID) == "Codex 產生；測試用 V-Log LUT。"
        let durableCuratedCube = curatedCube.withRecordID(curatedID)
        manifestCatalog.inferMissingOrigins(for: [durableCuratedCube])
        manifestCatalog.setOrigin(.unknown, for: [curatedID])
        manifestCatalog.inferMissingOrigins(for: [durableCuratedCube])
        let seededUnknownSurvivesRescan = manifestCatalog.origin(for: durableCuratedCube) == .unknown
        manifestCatalog.setDescription("使用者改寫", for: [curatedID])
        manifestCatalog.setOrigin(.custom, for: [curatedID])
        manifestCatalog.removeTag("完成色", from: [curatedID])
        manifestCatalog.seedCuratedMetadata(
            manifest.metadataByFingerprint,
            for: [curatedCube.withRecordID(curatedID)]
        )
        let userEditSurvivesRescan = manifestCatalog.record(for: curatedID)?.origin == .custom
            && manifestCatalog.record(for: curatedID)?.typedTags == ["相機風格"]
            && manifestCatalog.description(for: curatedID) == "使用者改寫"
        let manifestRelaunch = LUTCatalog(fileURL: manifestCatalogURL)
        let descriptionPersists = manifestRelaunch.description(for: curatedID) == "使用者改寫"
        let inputProfilePersists = manifestRelaunch.inputProfile(for: curatedCube.withRecordID(curatedID))
            == "Panasonic V-Log"

        // Records created before Brand metadata existed get one conservative
        // repair from an unambiguous folder/name. The migration is one-shot:
        // explicitly setting Unknown afterwards is a user choice and must win.
        let legacyBrandURL = root.appendingPathComponent("fuji/fuji-vlog-provia.cube")
        try FileManager.default.createDirectory(
            at: legacyBrandURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try cubeText.write(to: legacyBrandURL, atomically: true, encoding: .utf8)
        let legacyBrandLUT = try CubeLUT(url: legacyBrandURL, category: "fuji")
        guard let legacyBrandID = manifestCatalog.adoptSavedLUT(legacyBrandLUT) else { return false }
        let durableLegacyBrandLUT = legacyBrandLUT.withRecordID(legacyBrandID)
        manifestCatalog.inferMissingOrigins(for: [durableLegacyBrandLUT])
        let legacyBrandSeeded = manifestCatalog.origin(for: durableLegacyBrandLUT) == .vendor("Fujifilm")
        manifestCatalog.setOrigin(.unknown, for: [legacyBrandID])
        manifestCatalog.inferMissingOrigins(for: [durableLegacyBrandLUT])
        let legacyBrandUserEditWins = manifestCatalog.origin(for: durableLegacyBrandLUT) == .unknown

        let existingCustomURL = root.appendingPathComponent("sony/custom-look.cube")
        try FileManager.default.createDirectory(
            at: existingCustomURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try cubeText.write(to: existingCustomURL, atomically: true, encoding: .utf8)
        let existingCustomLUT = try CubeLUT(url: existingCustomURL, category: "sony")
        guard let existingCustomID = manifestCatalog.adoptSavedLUT(existingCustomLUT) else { return false }
        let durableExistingCustom = existingCustomLUT.withRecordID(existingCustomID)
        manifestCatalog.setOrigin(.custom, for: [existingCustomID])
        manifestCatalog.inferMissingOrigins(for: [durableExistingCustom])
        manifestCatalog.setOrigin(.unknown, for: [existingCustomID])
        manifestCatalog.inferMissingOrigins(for: [durableExistingCustom])
        let existingCustomUnknownSurvives = manifestCatalog.origin(for: durableExistingCustom) == .unknown

        let importedRoot = root.appendingPathComponent("Curated Import", isDirectory: true)
        let curatedImport = LUTLibrary.copyIn([curatedSource], to: importedRoot)
        let importedSidecar = importedRoot
            .appendingPathComponent(curatedSource.lastPathComponent, isDirectory: true)
            .appendingPathComponent(CuratedLUTManifest.fileName)
        let sidecarImportOK = curatedImport.imported == 1
            && FileManager.default.fileExists(atPath: importedSidecar.path)
            && (try? CuratedLUTManifest.load(from: importedSidecar)) != nil
        let curatedManifestOK = firstSeedOK && userEditSurvivesRescan
            && descriptionPersists && inputProfilePersists && sidecarImportOK
            && legacyBrandSeeded && legacyBrandUserEditWins
            && seededUnknownSurvivesRescan && existingCustomUnknownSurvives
            && lazyFileTableOK && lazyIdentityOK
        print("curated LUT manifest seeds Brand/Input/Tags/Description and repairs legacy Brand once -> \(curatedManifestOK ? "PASS" : "FAIL")")

        let curatorSource = root.appendingPathComponent("Curator Inputs", isDirectory: true)
        try FileManager.default.createDirectory(at: curatorSource, withIntermediateDirectories: true)
        let curatorA = curatorSource.appendingPathComponent("A.cube")
        let curatorDuplicate = curatorSource.appendingPathComponent("A duplicate.cube")
        let curatorTabbed = curatorSource.appendingPathComponent("tabbed.cube")
        let curatorLatin1 = curatorSource.appendingPathComponent("latin1.cube")
        let curator1D = curatorSource.appendingPathComponent("shaper.cube")
        try cubeText.write(to: curatorA, atomically: true, encoding: .utf8)
        try cubeText.write(to: curatorDuplicate, atomically: true, encoding: .utf8)
        try cubeText.replacingOccurrences(of: "LUT_3D_SIZE 2", with: "LUT_3D_SIZE\t2")
            .replacingOccurrences(of: "0.000000 0.000000 0.000000", with: "0.001000\t0.000000\t0.000000")
            .write(to: curatorTabbed, atomically: true, encoding: .utf8)
        let latin1Cube = "# Crème LUT\n" + cubeText.replacingOccurrences(
            of: "0.000000 0.000000 0.000000", with: "0.002000 0.000000 0.000000"
        )
        guard let latin1Data = latin1Cube.data(using: .isoLatin1) else { return false }
        try latin1Data.write(to: curatorLatin1)
        try "LUT_1D_SIZE 2\n0 0 0\n1 1 1\n".write(
            to: curator1D, atomically: true, encoding: .utf8
        )
        let curatedOutput = root.appendingPathComponent("Generated Corpus", isDirectory: true)
        let curatorResult = try LUTCorpusCurator.curate(
            sources: [
                .init(
                    id: "codex", label: "Codex",
                    description: "Codex 產生。", reference: nil, license: "project-owned"
                )
            ],
            candidates: [
                .init(
                    url: curatorA, sourceID: "codex", sourcePath: "A.cube",
                    destinationRelativePath: "Fujifilm/Codex/A.cube",
                    brand: "Fujifilm", inputProfile: "Panasonic V-Log",
                    tags: ["相機風格"], priority: 0
                ),
                .init(
                    url: curatorDuplicate, sourceID: "codex", sourcePath: "A duplicate.cube",
                    destinationRelativePath: "Fujifilm/Codex/A duplicate.cube",
                    brand: "Fujifilm", inputProfile: "Panasonic V-Log",
                    tags: ["相機風格"], priority: 1
                ),
                .init(
                    url: curatorTabbed, sourceID: "codex", sourcePath: "tabbed.cube",
                    destinationRelativePath: "Fujifilm/Codex/tabbed.cube",
                    brand: "Fujifilm", inputProfile: "Panasonic V-Log",
                    tags: ["相機風格"], priority: 1
                ),
                .init(
                    url: curatorLatin1, sourceID: "codex", sourcePath: "latin1.cube",
                    destinationRelativePath: "Fujifilm/Codex/latin1.cube",
                    brand: "Fujifilm", inputProfile: "Panasonic V-Log",
                    tags: ["相機風格"], priority: 1
                ),
                .init(
                    url: curator1D, sourceID: "codex", sourcePath: "shaper.cube",
                    destinationRelativePath: "Fujifilm/Codex/shaper.cube",
                    brand: "Fujifilm", inputProfile: "Panasonic V-Log",
                    tags: ["技術轉換"], priority: 2
                ),
            ],
            outputRoot: curatedOutput
        )
        let generatedManifest = try CuratedLUTManifest.load(
            from: curatedOutput.appendingPathComponent("LUTs/\(CuratedLUTManifest.fileName)")
        )
        let verifiedCorpus = try LUTCorpusCurator.verify(outputRoot: curatedOutput)
        let generatedActiveRoot = curatedOutput.appendingPathComponent("LUTs", isDirectory: true)
        let fastScanCatalog = LUTCatalog(fileURL: root.appendingPathComponent("fast-scan-catalog.json"))
        let fastScanLibrary = LUTLibrary(catalog: fastScanCatalog)
        fastScanLibrary.scan(generatedActiveRoot)
        await fastScanLibrary.scanCompletion()
        let authenticatedFastScanOK = fastScanLibrary.allLUTs.count == 3
            && fastScanLibrary.allLUTs.allSatisfy { $0.retainsTableData == false }

        // A changed file must not inherit the stale manifest fingerprint merely
        // because its relative path still matches.
        guard let changedEntry = generatedManifest.entries.first else { return false }
        let changedURL = generatedActiveRoot.appendingPathComponent(changedEntry.relativePath)
        let changedText = cubeText.replacingOccurrences(
            of: "0.000000 0.000000 0.000000", with: "0.125000 0.000000 0.000000"
        )
        try changedText.write(to: changedURL, atomically: true, encoding: .utf8)
        fastScanLibrary.scan(generatedActiveRoot)
        await fastScanLibrary.scanCompletion()
        let staleSidecarFallbackOK = fastScanLibrary.allLUTs.first {
            $0.url.standardizedFileURL == changedURL.standardizedFileURL
        }?.contentHash != changedEntry.sha256
        let rec709FolderProfileOK = LUTInputProfileInference.profile(
            relativePath: "Sony/Rec.709 to Color Grading LUTs/Soft Contrast.cube"
        ) == "Display / Rec.709"
        let curatorOK = curatorResult.active == 3
            && curatorResult.duplicates == 1
            && curatorResult.unsupported == 1
            && generatedManifest.entries.count == 3
            && generatedManifest.entries.first?.brand == "Fujifilm"
            && generatedManifest.entries.first?.inputProfile == "Panasonic V-Log"
            && verifiedCorpus.active == 3
            && authenticatedFastScanOK
            && staleSidecarFallbackOK
            && rec709FolderProfileOK
            && generatedManifest.entries.first?.tags == ["相機風格"]
            && FileManager.default.fileExists(
                atPath: curatedOutput.appendingPathComponent("LUTs/Fujifilm/Codex/A.cube").path
            )
            && FileManager.default.fileExists(
                atPath: curatedOutput.appendingPathComponent("Unsupported/Fujifilm/Codex/shaper.cube").path
            )
            && FileManager.default.fileExists(atPath: curatorA.path)
        print("repository LUT curator deduplicates and separates unsupported transforms -> \(curatorOK ? "PASS" : "FAIL")")

        var repositoryCorpusScanOK = true
        if let corpusPath = ProcessInfo.processInfo.environment["LUTCHECK_CORPUS"] {
            let corpusRoot = URL(fileURLWithPath: corpusPath, isDirectory: true)
            let corpusManifest = try CuratedLUTManifest.load(
                from: corpusRoot.appendingPathComponent(CuratedLUTManifest.fileName)
            )
            let corpusLibrary = LUTLibrary(
                catalog: LUTCatalog(fileURL: root.appendingPathComponent("corpus-scan-catalog.json"))
            )
            let started = ContinuousClock.now
            corpusLibrary.scan(corpusRoot)
            await corpusLibrary.scanCompletion()
            let elapsed = started.duration(to: .now)
            repositoryCorpusScanOK = corpusLibrary.allLUTs.count == corpusManifest.entries.count
                && corpusLibrary.allLUTs.allSatisfy { $0.retainsTableData == false }
                && elapsed < .seconds(30)
            print("repository corpus authenticated lazy scan \(corpusLibrary.allLUTs.count) LUTs in \(elapsed) -> \(repositoryCorpusScanOK ? "PASS" : "FAIL")")
        }

        let brandShelves = recoveryViewModel.libraryDiscoveryShelves(for: .brand)
        let tagShelves = recoveryViewModel.libraryDiscoveryShelves(for: .tag)
        let collectionShelves = recoveryViewModel.libraryDiscoveryShelves(for: .collectionAndStar)
        let folderShelves = recoveryViewModel.libraryDiscoveryShelves(for: .folder)
        let brandOK = brandShelves.first(where: { $0.title == "Custom" })?.luts.map(\.lutID).contains(firstID) == true
            && brandShelves.first(where: { $0.title == "Unknown" })?.luts.map(\.lutID).contains(secondID) == true
        let tagOK = tagShelves.first(where: { $0.title == "soft" })?.luts.map(\.lutID) == [firstID]
            && tagShelves.contains(where: { $0.title.hasPrefix("input:") }) == false
            && tagShelves.contains(where: { $0.title == "Custom" || $0.title == "Unknown" }) == false
        let collectionOK = Set(
            collectionShelves.first(where: { $0.title == "低飽和" })?.luts.map(\.lutID) ?? []
        ) == Set([firstID, secondID])
            && collectionShelves.first?.id == "starred"
            && collectionShelves.first?.luts.map(\.lutID) == [firstID]
        let folderOK = Set(
            folderShelves.first(where: { $0.title == "General" })?.luts.map(\.lutID) ?? []
        ).isSuperset(of: [firstID, secondID])
        let folderCube = [SIMD3<Float>](repeating: .zero, count: 8)
        let nestedFolderLUTs = [
            CubeLUT(cube: folderCube, size: 2, name: "Film Direct", category: "Fuji/Film"),
            CubeLUT(cube: folderCube, size: 2, name: "Kodak", category: "Fuji/Film/Kodak"),
            CubeLUT(cube: folderCube, size: 2, name: "BW", category: "Fuji/BW"),
        ]
        let topFolders = LUTLibraryDiscovery.folderShelves(
            from: nestedFolderLUTs, selectedFolder: nil
        )
        let fujiFolders = LUTLibraryDiscovery.folderShelves(
            from: nestedFolderLUTs, selectedFolder: "Fuji"
        )
        let filmFolders = LUTLibraryDiscovery.folderShelves(
            from: Array(nestedFolderLUTs.prefix(2)), selectedFolder: "Fuji/Film"
        )
        let folderHierarchyOK = topFolders.count == 1
            && topFolders.first?.title == "Fuji"
            && topFolders.first?.luts.count == 3
            && fujiFolders.first(where: { $0.title == "Film" })?.luts.count == 2
            && fujiFolders.first(where: { $0.title == "BW" })?.luts.count == 1
            && filmFolders.first(where: { $0.title == "Film" })?.luts.count == 1
            && filmFolders.first(where: { $0.title == "Kodak" })?.luts.count == 1
        recoveryViewModel.setLUTSource(.collection(collection.id), for: .library)
        let scopedCount = recoveryViewModel.libraryDiscoveryShelves(for: .brand)
            .reduce(0) { $0 + $1.luts.count }
        let discoveryOK = brandOK && tagOK && collectionOK && folderOK
            && folderHierarchyOK && scopedCount == 2
        recoveryViewModel.setLUTSource(.all, for: .library)
        print("LUT discovery Folder/Collection & Star/Brand/Tag shelves and source scope -> \(discoveryOK ? "PASS" : "FAIL")")

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
            && media.records.first(where: { $0.kind == .image })?.canOpenInViewer == true
            && media.records.first(where: { $0.kind == .video })?.canOpenInViewer == false
            && Set(relaunchedMedia.records.map(\.id)) == mediaIDs
            && relaunchedMedia.records.contains { $0.logicalPath == "Shoot/Day 1/frame.png" }
        print("durable Media Library -> \(mediaOK ? "PASS" : "FAIL")")
        return catalogOK && mixedSelectionTagOK && visibleTagEditingOK && recoveryOK
            && recoveredSessionOK && discoveryOK && focusRecoveryOK
            && managerBrandColumnOK && curatedManifestOK && curatorOK
            && repositoryCorpusScanOK
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
