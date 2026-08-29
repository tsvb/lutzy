import AppKit
import Foundation
@testable import LUTzyKit

@MainActor
func runGallerySearchCoalescingCheck() async -> Bool {
    let search = LUTGallerySearchState(debounce: .milliseconds(40))
    search.submit("c")
    search.submit("cl")
    search.submit("classic")
    let immediateOK = search.query.isEmpty
    try? await Task.sleep(for: .milliseconds(20))
    let midBurstOK = search.query.isEmpty
    try? await Task.sleep(for: .milliseconds(40))
    let settledOK = search.query == "classic"
    search.submit("")
    let clearOK = search.query.isEmpty
    let ok = immediateOK && midBurstOK && settledOK && clearOK
    print("gallery search publishes one settled query per typing burst -> \(ok ? "PASS" : "FAIL")")
    return ok
}

private actor ViewerPerformanceRenderEngine: RenderEngining {
    struct Request {
        let source: ImageSource
        let document: EditDocument
        let lutID: LUTID?
        let scale: RenderScale
    }

    private(set) var requests: [Request] = []
    var previewCount: Int { requests.count }

    func makeCGImage(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace
    ) -> sending CGImage? {
        requests.append(Request(
            source: source, document: document, lutID: lut?.lutID, scale: scale
        ))
        let colourSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: 2, height: 2,
            bitsPerComponent: 8, bytesPerRow: 8,
            space: colourSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(red: 0.4, green: 0.5, blue: 0.6, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return context.makeImage()
    }

    func encode(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        format: ExportFormat,
        quality: CGFloat,
        space: WorkingSpace
    ) throws -> Data { Data() }

    func histogram(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace,
        maxDimension: Int
    ) -> HistogramData? { nil }

    func invalidateLUTCache() {}
    func rawCapabilities(for source: ImageSource) -> RAWCapabilities? { nil }
}

@MainActor
func runImportReviewVisualComparisonCheck() async -> Bool {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("lutcheck-import-review-preview-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try identityCube(size: 2).write(
            to: root.appendingPathComponent("Imported.cube"), atomically: true, encoding: .utf8
        )
        try identityCube(size: 3).write(
            to: root.appendingPathComponent("Similar.cube"), atomically: true, encoding: .utf8
        )
        let catalog = LUTCatalog(fileURL: root.appendingPathComponent("catalog.json"))
        let library = LUTLibrary(catalog: catalog)
        library.scan(root)
        while library.isScanning { try? await Task.sleep(for: .milliseconds(10)) }
        guard library.allLUTs.count == 2 else { return false }

        let engine = ViewerPerformanceRenderEngine()
        let viewModel = AppViewModel(engine: engine, library: library)
        let importedID = library.allLUTs[0].lutID
        let matchID = library.allLUTs[1].lutID
        let size = CGSize(width: 640, height: 400)
        let imported = await viewModel.makeLUTImportReviewPreview(for: importedID, maxSize: size)
        let match = await viewModel.makeLUTImportReviewPreview(for: matchID, maxSize: size)
        let requests = await engine.requests
        let sameSample = requests.count == 2 && requests[0].source == requests[1].source
        let samePipeline = requests.count == 2
            && requests.allSatisfy {
                $0.document.rawDevelop == .neutral
                    && $0.document.adjustments.isEmpty
                    && $0.document.lut.intensity == 1
                    && $0.document.sourceSpace == LUTLibrarySample.default.sourceSpace
                    && $0.scale == .preview(maxSize: size)
            }
        let correctLUTs = requests.map(\.lutID) == [importedID, matchID]
        let ok = imported != nil && match != nil && sameSample && samePipeline && correctLUTs
        print("import recommendations render both LUTs on one fixed sample -> \(ok ? "PASS" : "FAIL")")
        return ok
    } catch {
        print("import recommendation visual comparison -> FAIL (\(error))")
        return false
    }
}

@MainActor
func runGridSelectionRenderScopeCheck() async -> Bool {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("lutcheck-grid-performance-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let lutRoot = root.appendingPathComponent("LUTs", isDirectory: true)
        try FileManager.default.createDirectory(at: lutRoot, withIntermediateDirectories: true)
        try identityCube(size: 2).write(
            to: lutRoot.appendingPathComponent("A.cube"), atomically: true, encoding: .utf8
        )
        try identityCube(size: 3).write(
            to: lutRoot.appendingPathComponent("B.cube"), atomically: true, encoding: .utf8
        )

        let catalog = LUTCatalog(fileURL: root.appendingPathComponent("catalog.json"))
        let library = LUTLibrary(catalog: catalog)
        library.scan(lutRoot)
        while library.isScanning { try? await Task.sleep(for: .milliseconds(10)) }
        guard library.allLUTs.count == 2 else { return false }

        let imageURL = root.appendingPathComponent("source.jpg")
        guard writeJPEG(description: nil, to: imageURL, colourful: true) else { return false }
        let engine = ViewerPerformanceRenderEngine()
        let viewModel = AppViewModel(
            engine: engine,
            projects: ProjectStore(root: root.appendingPathComponent("Projects")),
            tags: LUTTagStore(fileURL: root.appendingPathComponent("tags.json")),
            media: MediaLibrary(
                root: root.appendingPathComponent("Media"),
                manifestURL: root.appendingPathComponent("media.json")
            ),
            library: library
        )
        viewModel.openImage(url: imageURL)
        while viewModel.imageSource == nil { try? await Task.sleep(for: .milliseconds(10)) }
        viewModel.setLayout(.grid2x2)
        for task in Array(viewModel.cellTasks.values) { await task.value }

        let current = viewModel.cellLUTIDs[0]
        guard let replacement = library.allLUTs.first(where: { $0.lutID != current }) else {
            return false
        }
        let before = await engine.previewCount
        viewModel.activateGridCell(0)
        viewModel.chooseLUTFromGallery(replacement)
        if let task = viewModel.cellTasks[0] { await task.value }
        try? await Task.sleep(for: .milliseconds(20))
        let assignmentCount = await engine.previewCount - before

        let beforeExit = await engine.previewCount
        viewModel.setLayout(.single)
        try? await Task.sleep(for: .milliseconds(20))
        let exitCount = await engine.previewCount - beforeExit
        let ok = assignmentCount == 1 && exitCount == 1
        print("grid LUT assignment renders one cell; exiting grid renders main once -> \(ok ? "PASS" : "FAIL")")
        return ok
    } catch {
        print("grid LUT assignment render scope -> FAIL (\(error))")
        return false
    }
}

func runLibraryBootstrapCheck() -> Bool {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("lutcheck-library-bootstrap-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    do {
        let appSupport = root.appendingPathComponent("Application Support LUTs", isDirectory: true)
        let repository = root.appendingPathComponent("Repository LUTs", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try Data("{}".utf8).write(
            to: repository.appendingPathComponent(CuratedLUTManifest.fileName)
        )
        let repositoryOK = LUTLibrary.resolveManagedFolder(
            applicationSupportFolder: appSupport,
            repositoryCandidate: repository
        ).standardizedFileURL == repository.standardizedFileURL
        try FileManager.default.removeItem(
            at: repository.appendingPathComponent(CuratedLUTManifest.fileName)
        )
        let fallbackOK = LUTLibrary.resolveManagedFolder(
            applicationSupportFolder: appSupport,
            repositoryCandidate: repository
        ).standardizedFileURL == appSupport.standardizedFileURL
        let ok = repositoryOK && fallbackOK
        print("curated repository is the default managed Library -> \(ok ? "PASS" : "FAIL")")
        return ok
    } catch {
        print("curated repository is the default managed Library -> FAIL (\(error))")
        return false
    }
}

func runCuratedCorpusPolicyCheck() -> Bool {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let manifestURL = root
        .appendingPathComponent("LUTLibrary/LUTs", isDirectory: true)
        .appendingPathComponent(CuratedLUTManifest.fileName)

    do {
        let manifest = try CuratedLUTManifest.load(from: manifestURL)
        let activeSources = Set(manifest.entries.map(\.sourceID))
        let clusterValues = Set(LUTVisualCluster.allCases.map(\.rawValue))
        let clustered = manifest.entries.filter {
            guard let value = $0.visualCluster else { return false }
            return clusterValues.contains(value)
        }
        let ok = manifest.sources["codex-generated"] == nil
            && activeSources.contains("codex-generated") == false
            && manifest.sources["claude-generated"] != nil
            && activeSources.contains("claude-generated")
            && manifest.entries.count == 1_876
            && clustered.count == manifest.entries.count
        print("curated corpus removes Codex and clusters all 1,876 LUTs -> \(ok ? "PASS" : "FAIL")")
        return ok
    } catch {
        print("curated corpus removes Codex and clusters all 1,876 LUTs -> FAIL (\(error))")
        return false
    }
}

func runVisualClusterClassificationCheck() -> Bool {
    func metrics(
        chroma: Double,
        hue: Double,
        mono: Double = 0.1,
        saturation: Double = 1,
        highlightChroma: Double? = nil,
        highlightHue: Double? = nil
    ) -> LUTMetrics {
        LUTMetrics(
            contrast: 1, saturation: saturation, monoSpread: mono,
            blackLevel: 0, whiteLevel: 1,
            shadowChroma: chroma, highlightChroma: highlightChroma ?? chroma,
            shadowHue: hue, highlightHue: highlightHue ?? hue,
            splitAngle: 0, skinRatio: 1
        )
    }
    let cases: [(LUTMetrics, LUTVisualCluster)] = [
        (metrics(chroma: 0.02, hue: 45), .warmBrown),
        (metrics(chroma: 0.02, hue: 120), .yellowGreen),
        (metrics(chroma: 0.02, hue: 190), .cyanGreen),
        (metrics(chroma: 0.02, hue: 250), .coolBlue),
        (metrics(chroma: 0.02, hue: 320), .purpleMagenta),
        (metrics(chroma: 0.02, hue: 5), .warmRed),
        (metrics(chroma: 0.02, hue: 45, mono: 0), .monochrome),

        // An untinted neutral is not one visual family: the corpus spreads it
        // evenly across every saturation class, so saturation — which stays
        // measurable when the neutral axis carries no chroma — names it.
        (metrics(chroma: 0.001, hue: 45, saturation: 1.4), .neutralVivid),
        (metrics(chroma: 0.001, hue: 45, saturation: 1.0), .neutralNatural),
        (metrics(chroma: 0.001, hue: 45, saturation: 0.6), .neutralFlat),

        // Both ends of the ramp are evidence for one tint. Deciding the family
        // on whichever end happens to be stronger puts a family boundary on a
        // hairline chroma comparison: these two differ by 0.0002 and must not
        // land in different families.
        (
            metrics(chroma: 0.0061, hue: 15, highlightChroma: 0.0060, highlightHue: 45),
            .warmBrown
        ),
        (
            metrics(chroma: 0.0060, hue: 15, highlightChroma: 0.0062, highlightHue: 45),
            .warmBrown
        ),

        // Opposed ends are a split tone, not a cancelled one. Summing them
        // would read a visible teal/orange grade as untinted grey, so the
        // stronger end still decides.
        (
            metrics(chroma: 0.012, hue: 220, highlightChroma: 0.011, highlightHue: 40),
            .coolBlue
        ),
    ]
    let failures = cases.filter { LUTVisualCluster.classify($0.0) != $0.1 }
    for (m, expected) in failures {
        print("  cluster mismatch: expected \(expected.rawValue), got \(LUTVisualCluster.classify(m).rawValue)")
    }
    let ok = failures.isEmpty
    print("visual cluster boundaries are deterministic -> \(ok ? "PASS" : "FAIL")")
    return ok
}

@MainActor
func runLibrarySourceMetadataCheck() -> Bool {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("lutcheck-library-source-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cubeURL = root.appendingPathComponent("A.cube")
        try identityCube(size: 2).write(to: cubeURL, atomically: true, encoding: .utf8)
        let cube = try CubeLUT(url: cubeURL)
        let manifestURL = root.appendingPathComponent(CuratedLUTManifest.fileName)
        let manifestJSON = """
        {
          "version": 1,
          "sources": {
            "claude": {
              "label": "Claude Generated",
              "description": "Claude source",
              "reference": null,
              "license": "project-owned"
            }
          },
          "entries": [{
            "relativePath": "A.cube",
            "sha256": "\(cube.contentHash)",
            "brand": "Fujifilm",
            "inputProfile": "Panasonic V-Log",
            "tags": ["相機風格"],
            "sourceID": "claude",
            "visualCluster": "暖褐／咖啡",
            "description": null
          }],
          "duplicates": [],
          "unsupported": []
        }
        """
        try manifestJSON.write(to: manifestURL, atomically: true, encoding: .utf8)
        let manifest = try CuratedLUTManifest.load(from: manifestURL)
        let catalogURL = root.appendingPathComponent("catalog.json")
        let catalog = LUTCatalog(fileURL: catalogURL)
        guard let id = catalog.adoptSavedLUT(cube) else { return false }
        guard let firstCluster = catalog.createCollection(named: "色調 · 暖褐／咖啡"),
              let duplicateCluster = catalog.createCollection(named: "色調 · 暖褐／咖啡")
        else { return false }
        let durable = cube.withRecordID(id)
        catalog.seedCuratedMetadata(manifest.metadataByFingerprint, for: [durable])
        let relaunched = LUTCatalog(fileURL: catalogURL)
        let seededMembership = catalog.members(of: firstCluster.id) == [id]
            && catalog.members(of: duplicateCluster.id).isEmpty
        let seededMembershipPersists = relaunched.collections.contains(where: { $0.id == firstCluster.id })
            && relaunched.members(of: firstCluster.id) == [id]
        catalog.setMembership(false, collectionID: firstCluster.id, recordIDs: [id])
        catalog.seedCuratedMetadata(manifest.metadataByFingerprint, for: [durable])
        let userRemovalSurvivesRescan = catalog.members(of: firstCluster.id).isEmpty
        let ok = catalog.sourceLabel(for: durable) == "Claude Generated"
            && relaunched.sourceLabel(for: durable) == "Claude Generated"
            && seededMembership
            && seededMembershipPersists
            && userRemovalSurvivesRescan
        print("curated Source distinguishes same-named LUTs after relaunch -> \(ok ? "PASS" : "FAIL")")
        return ok
    } catch {
        print("curated Source distinguishes same-named LUTs after relaunch -> FAIL (\(error))")
        return false
    }
}

func runFolderNavigationNoiseCheck() -> Bool {
    let counts = [
        "Canon/Documents Collection/3dlut/17grid-3dlut/full-to-full-range": 25,
        "Canon/Documents Collection/3dlut/33grid-3dlut/full-to-full-range": 25,
        "CINECOLOR/CINECOLOR/A24": 3,
    ]
    let tree = LUTFolderHierarchy.tree(from: counts)
    let canonChildren = tree.first(where: { $0.name == "Canon" })?.children.map(\.name) ?? []
    let cineChildren = tree.first(where: { $0.name == "CINECOLOR" })?.children.map(\.name) ?? []

    let cube = [SIMD3<Float>](repeating: .zero, count: 8)
    let canonLUTs = [
        CubeLUT(
            cube: cube, size: 2, name: "17 grid",
            category: "Canon/Documents Collection/3dlut/17grid-3dlut/full-to-full-range"
        ),
        CubeLUT(
            cube: cube, size: 2, name: "33 grid",
            category: "Canon/Documents Collection/3dlut/33grid-3dlut/full-to-full-range"
        ),
    ]
    let shelfTitles = LUTLibraryDiscovery.folderShelves(
        from: canonLUTs, selectedFolder: "Canon"
    ).map(\.title)
    let authoredLevels = (1...12).map { "Authored \($0)" }
    let authoredTree = LUTFolderHierarchy.tree(from: [authoredLevels.joined(separator: "/"): 1])
    var preserved: [String] = []
    var cursor = authoredTree.first
    while let node = cursor {
        preserved.append(node.name)
        cursor = node.children.first
    }
    let ok = canonChildren == ["17grid-3dlut", "33grid-3dlut"]
        && cineChildren == ["A24"]
        && shelfTitles == ["17grid-3dlut", "33grid-3dlut"]
        && preserved == authoredLevels
    print("Folder navigation hides provenance/format wrappers -> \(ok ? "PASS" : "FAIL")")
    return ok
}

func runCuratedPathCompactionCheck() -> Bool {
    let cases: [(path: String, brand: String, source: String, expected: String)] = [
        (
            "Apple/Documents Collection/AppleLogToRec709-v1.0.cube",
            "Apple", "documents-collection",
            "Apple/AppleLogToRec709-v1.0.cube"
        ),
        (
            "Blackmagic Design/Documents Collection/DaVinci Resolve/Blackmagic Design/Blackmagic Film to Rec709.cube",
            "Blackmagic Design", "documents-collection",
            "Blackmagic Design/Blackmagic Film to Rec709.cube"
        ),
        (
            "Canon/Documents Collection/3dlut/17grid-3dlut/full-to-full-range/Canon Log.cube",
            "Canon", "documents-collection",
            "Canon/Canon Log.cube"
        ),
        (
            "ARRI/V-Log Alchemy/Arri/Classic.cube",
            "ARRI", "vlog-alchemy",
            "ARRI/V-Log Alchemy/Classic.cube"
        ),
        (
            "CINECOLOR/CINECOLOR/A24/Florida.cube",
            "CINECOLOR", "cinecolor",
            "CINECOLOR/A24/Florida.cube"
        ),
        (
            "FilterGrade/FilterGrade Free Cine v2/Warm.cube",
            "FilterGrade", "filtergrade-free-cine-v2",
            "FilterGrade/Free Cine v2/Warm.cube"
        ),
        (
            "G-MIC Film LUTs/Film-Luts/negative_new/Film.cube",
            "G'MIC Film LUTs", "gmic-film-luts",
            "G'MIC Film LUTs/negative_new/Film.cube"
        ),
    ]
    let failures = cases.filter { item in
        LUTCorpusCurator.compactRelativePath(
            item.path, brand: item.brand, sourceID: item.source
        ) != item.expected
    }
    let rulesOK = failures.isEmpty
    if rulesOK == false {
        for item in failures {
            let actual = LUTCorpusCurator.compactRelativePath(
                item.path, brand: item.brand, sourceID: item.source
            )
            print("  \(item.path) -> \(actual), expected \(item.expected)")
        }
    }
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("lutcheck-path-compact-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var transactionOK = false
    do {
        let oldFolder = root.appendingPathComponent(
            "LUTs/Apple/Documents Collection", isDirectory: true
        )
        try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
        let oldFile = oldFolder.appendingPathComponent("AppleLogToRec709-v1.0.cube")
        try identityCube(size: 2).write(to: oldFile, atomically: true, encoding: .utf8)
        let lut = try CubeLUT(url: oldFile)
        let fileHash = try CubeLUT.fileSHA256(at: oldFile)
        let manifest = """
        {
          "version": 1,
          "sources": {
            "documents-collection": {
              "label": "Documents LUT collection",
              "description": "Local source",
              "license": "Local only"
            }
          },
          "entries": [{
            "relativePath": "Apple/Documents Collection/AppleLogToRec709-v1.0.cube",
            "sha256": "\(lut.contentHash)",
            "fileSHA256": "\(fileHash)",
            "brand": "Apple",
            "inputProfile": "Apple Log",
            "tags": ["技術轉換"],
            "sourceID": "documents-collection",
            "visualCluster": "中性自然",
            "description": "Apple Log transform"
          }],
          "duplicates": [{
            "sourcePath": "Original/duplicate.cube",
            "canonicalRelativePath": "Apple/Documents Collection/AppleLogToRec709-v1.0.cube",
            "sha256": "\(lut.contentHash)"
          }],
          "unsupported": []
        }
        """
        try manifest.write(
            to: root.appendingPathComponent("LUTs/.lutzy-library.json"),
            atomically: true, encoding: .utf8
        )

        let result = try LUTCorpusCurator.compactHierarchy(outputRoot: root)
        let newFile = root.appendingPathComponent("LUTs/Apple/AppleLogToRec709-v1.0.cube")
        let savedManifest = try String(
            contentsOf: root.appendingPathComponent("LUTs/.lutzy-library.json"), encoding: .utf8
        )
        let savedReadme = try String(
            contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8
        )
        let savedAudit = try String(
            contentsOf: root.appendingPathComponent("SOURCE_AUDIT.md"), encoding: .utf8
        )
        let compactedFileHash = try CubeLUT.fileSHA256(at: newFile)
        transactionOK = result == .init(total: 1, moved: 1, collisions: 0)
            && FileManager.default.fileExists(atPath: oldFile.path) == false
            && FileManager.default.fileExists(atPath: newFile.path)
            && compactedFileHash == fileHash
            && savedManifest.contains("Apple/AppleLogToRec709-v1.0.cube")
            && savedManifest.contains("Documents Collection") == false
            && savedReadme.contains("<Brand>/<meaningful pack>/")
            && savedAudit.contains("`LUTs/Apple/AppleLogToRec709-v1.0.cube`")
            && savedAudit.contains("LUTs/Apple/Documents Collection") == false
    } catch {
        print("  compact transaction failed: \(error)")
    }
    let ok = rulesOK && transactionOK
    print("curated physical paths remove metadata and packaging wrappers -> \(ok ? "PASS" : "FAIL")")
    return ok
}

@MainActor
func runDurableLibraryChecks() async -> Bool {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("lutcheck-library-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let libraryBootstrapOK = runLibraryBootstrapCheck()

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
        let materializationCache = LUTMaterializationCache(capacity: 1)
        let cachedFirst = await materializationCache.materialized(first)
        let cachedProbe = await materializationCache.sample([0.5, 0.5, 0.5], from: first)
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
        let currentReplacement = try CubeLUT(url: replacedURL)
        let cancelledMaterialization = Task {
            await materializationCache.materialized(currentReplacement)
        }
        cancelledMaterialization.cancel()
        let cancelledParseOK = await cancelledMaterialization.value == nil
        async let rematerializedFirst = materializationCache.materialized(first)
        async let materializedReplacement = materializationCache.materialized(currentReplacement)
        let concurrentResults = await (rematerializedFirst, materializedReplacement)
        let cachedCount = await materializationCache.count
        let peakParseCount = await materializationCache.peakParseCount
        let boundedUICacheOK = cachedFirst?.retainsTableData == true
            && cachedProbe?.count == 3
            && concurrentResults.0 != nil
            && concurrentResults.1 != nil
            && cancelledParseOK
            && cachedCount == 1
            && peakParseCount == 1
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
            && manifestCatalog.sourceLabel(for: curatedCube.withRecordID(curatedID)) == "Codex"
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
            && lazyFileTableOK && lazyIdentityOK && boundedUICacheOK
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
        let cinecolorDownloaded = DownloadedLUTClassifier.classify(
            relativePath: "CINECOLOR_A24_/CUBE/FLORIDA.cube"
        )
        let cinecolorDownloadedOK = cinecolorDownloaded.brand == "CINECOLOR"
            && cinecolorDownloaded.sourceID == "cinecolor"
            && cinecolorDownloaded.destinationSubpath == "A24/FLORIDA.cube"
            && cinecolorDownloaded.inputProfile == "Unknown"
            && cinecolorDownloaded.tags.contains("電影風格")
        let cinecolorDocumentedAlias = DownloadedLUTClassifier.classify(
            relativePath: "BEAUTY/CUBE/BEAUTY_01.cube"
        )
        let cinecolorAliasOK = cinecolorDocumentedAlias.brand == "CINECOLOR"
            && cinecolorDocumentedAlias.destinationSubpath == "BEAUTY/BEAUTY_01.cube"
            && cinecolorDocumentedAlias.tags.contains("人像")
        let smallHDDownloaded = DownloadedLUTClassifier.classify(
            relativePath: "SmallHD+LUT+Pack_Movie+Looks+2/Canon/Arrakis-CLog2.cube"
        )
        let smallHDDownloadedOK = smallHDDownloaded.brand == "SmallHD"
            && smallHDDownloaded.sourceID == "smallhd-movie-looks-2"
            && smallHDDownloaded.destinationSubpath == "Canon/Arrakis-CLog2.cube"
            && smallHDDownloaded.inputProfile == "Canon C-Log 2"
            && smallHDDownloaded.tags.contains("電影風格")
        let smallHDInputBoundariesOK = DownloadedLUTClassifier.classify(
            relativePath: "SmallHD+LUT+Pack_Movie+Looks+2/Arri/Cliff-LogC4.cube"
        ).inputProfile == "ARRI LogC4"
            && DownloadedLUTClassifier.classify(
                relativePath: "SmallHD+LUT+Pack_Movie+Looks+2/RED/Gems-Log3G10.cube"
            ).inputProfile == "RED Log3G10"
            && DownloadedLUTClassifier.classify(
                relativePath: "SmallHD+LUT+Pack_Movie+Looks+2/Panasonic/Arrakis-VLog.cube"
            ).inputProfile == "Panasonic V-Log"
            && LUTInputProfileInference.profile(
                relativePath: "DJI/P4DeLOGCube/DJI_Phantom4_DLOG2Rec709.cube"
            ) == "DJI D-Log"
        let printFilmDownloaded = DownloadedLUTClassifier.classify(
            relativePath: "Print+Film+Emulation+LUTs/Rec709_Kodak_2383_D65.cube"
        )
        let printFilmDownloadedOK = printFilmDownloaded.brand == "Kodak"
            && printFilmDownloaded.sourceID == "print-film-emulation"
            && printFilmDownloaded.inputProfile == "Display / Rec.709"
            && printFilmDownloaded.tags.contains("底片模擬")
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
            && cinecolorDownloadedOK
            && cinecolorAliasOK
            && smallHDDownloadedOK
            && smallHDInputBoundariesOK
            && printFilmDownloadedOK
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
        return libraryBootstrapOK && catalogOK && mixedSelectionTagOK && visibleTagEditingOK && recoveryOK
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

/// A visual family is a measurement, so changing the rules has to move an
/// already-seeded Library. This proves the reseed moves the record, preserves
/// the old Collection for explicit user review, and then stops doing anything.
@MainActor
func runVisualClusterReseedCheck() -> Bool {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("lutcheck-cluster-reseed-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cubeURL = root.appendingPathComponent("look.cube")
        try identityCube(size: 2).write(to: cubeURL, atomically: true, encoding: .utf8)
        let cube = try CubeLUT(url: cubeURL)
        let catalogURL = root.appendingPathComponent("catalog.json")

        let metadata: [String: CuratedLUTMetadata] = [
            cube.contentHash: CuratedLUTMetadata(
                seedID: "manifest-v1:\(cube.contentHash)",
                fingerprint: cube.contentHash,
                origin: .vendor("Fujifilm"),
                sourceLabel: "Test",
                inputProfile: "Panasonic V-Log",
                tags: ["完成色"],
                visualCluster: .cyanGreen,
                description: "測試用"
            ),
        ]

        let catalog = LUTCatalog(fileURL: catalogURL)
        guard let recordID = catalog.adoptSavedLUT(cube) else { return false }
        catalog.seedCuratedMetadata(metadata, for: [cube.withRecordID(recordID)])
        let freshSeedOK = catalog.record(for: recordID)?.curatedVisualClusterSeed
            == "visual-cluster-v2:青綠"

        // Rewrite the persisted catalog into what an install seeded by the
        // previous rules looks like: a v1 marker and the Collection that
        // version's family name created.
        let staleJSON = try String(contentsOf: catalogURL, encoding: .utf8)
            .replacingOccurrences(of: "visual-cluster-v2:青綠", with: "visual-cluster-v1:近中性")
            .replacingOccurrences(of: "色調 · 青綠", with: "色調 · 近中性")
        try staleJSON.write(to: catalogURL, atomically: true, encoding: .utf8)

        let reopened = LUTCatalog(fileURL: catalogURL)
        let staleOK = reopened.record(for: recordID)?.curatedVisualClusterSeed
            == "visual-cluster-v1:近中性"
            && reopened.collections.contains { $0.name == "色調 · 近中性" }

        reopened.seedCuratedMetadata(metadata, for: [cube.withRecordID(recordID)])
        guard let moved = reopened.record(for: recordID),
              let currentID = reopened.collections.first(where: { $0.name == "色調 · 青綠" })?.id
        else { return false }
        let reseedOK = moved.curatedVisualClusterSeed == "visual-cluster-v2:青綠"
            && moved.collectionIDs.contains(currentID)
            && moved.collectionIDs.count == 1
            && reopened.collections.contains { $0.name == "色調 · 近中性" }

        // Seeding is idempotent once current: a rescan must not keep churning
        // Collections or rewriting the catalog.
        let before = reopened.collections.map(\.id)
        reopened.seedCuratedMetadata(metadata, for: [cube.withRecordID(recordID)])
        let idempotentOK = reopened.collections.map(\.id) == before
            && reopened.record(for: recordID)?.collectionIDs == moved.collectionIDs

        let ok = freshSeedOK && staleOK && reseedOK && idempotentOK
        if ok == false {
            print("  fresh=\(freshSeedOK) stale=\(staleOK) reseed=\(reseedOK) idempotent=\(idempotentOK)")
        }
        print("visual cluster reseed moves a stale Library and preserves the old Collection -> \(ok ? "PASS" : "FAIL")")
        return ok
    } catch {
        print("visual cluster reseed moves a stale Library and preserves the old Collection -> FAIL (\(error))")
        return false
    }
}
