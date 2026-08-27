import Foundation
import LUTzyKit

private struct Arguments {
    var output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("LUTLibrary", isDirectory: true)
    var film = URL(fileURLWithPath: "/Users/world4jason/code_ground/Film-Luts", isDirectory: true)
    var codex = URL(fileURLWithPath: "/Users/world4jason/code_ground/lut", isDirectory: true)
    var claude = URL(fileURLWithPath: "/Users/world4jason/code_ground/claude lut", isDirectory: true)
    var alchemy = URL(fileURLWithPath: "/Users/world4jason/code_ground/V-Log-Alchemy", isDirectory: true)
    var documents = URL(fileURLWithPath: "/Users/world4jason/Documents/luts", isDirectory: true)
    var downloads = URL(
        fileURLWithPath: "/Users/world4jason/Downloads/Downloaded Luts/lut unzip",
        isDirectory: true
    )
    var verify: URL?

    init(_ values: [String]) throws {
        var index = 1
        while index < values.count {
            let key = values[index]
            guard index + 1 < values.count else { throw CLIError.missingValue(key) }
            let url = URL(fileURLWithPath: values[index + 1], isDirectory: true)
            switch key {
            case "--output": output = url
            case "--film-luts": film = url
            case "--codex": codex = url
            case "--claude": claude = url
            case "--vlog-alchemy": alchemy = url
            case "--documents": documents = url
            case "--downloads": downloads = url
            case "--verify": verify = url
            default: throw CLIError.unknownArgument(key)
            }
            index += 2
        }
    }
}

private enum CLIError: LocalizedError {
    case missingValue(String)
    case unknownArgument(String)
    case missingDirectory(URL)

    var errorDescription: String? {
        switch self {
        case .missingValue(let key): return "Missing value after \(key)."
        case .unknownArgument(let value): return "Unknown argument \(value)."
        case .missingDirectory(let url): return "Required source directory does not exist: \(url.path)"
        }
    }
}

private let sources: [LUTCorpusCurator.SourceDefinition] = [
    .init(
        id: "codex-generated",
        label: "Codex-generated LUTs",
        description: "Codex 產生；為 LUMIX S9 建立的 V-Log/V-Gamut 完成色 LUT，包含 Sony、RICOH 與 Fujifilm 方向性風格及中性技術檢查。",
        reference: "local project: code_ground/lut",
        license: "Project-generated; publication status to be confirmed"
    ),
    .init(
        id: "claude-generated",
        label: "Claude-generated LUTs",
        description: "Claude 產生；為 LUMIX S9 建立的 V-Log/V-Gamut 至 Rec.709/sRGB 完成色 LUT。",
        reference: "local project: code_ground/claude lut",
        license: "Project-generated; publication status to be confirmed"
    ),
    .init(
        id: "vlog-alchemy",
        label: "V-Log Alchemy",
        description: "來自 GitHub 專案 shenmintao/V-Log-Alchemy；將 V-Log/V-Gamut 轉為多家相機與底片方向的完成色 LUT。",
        reference: "https://github.com/shenmintao/V-Log-Alchemy",
        license: "Apache-2.0"
    ),
    .init(
        id: "gmic-film-luts",
        label: "G'MIC Film LUTs Collection",
        description: "來自 GitHub 專案 YahiaAngelo/Film-Luts（G'MIC Film LUTs Collection）。上游以 MIT 提供，但 README 提醒個別 LUT 可能另有權利；發佈二進位 corpus 前仍需複核。",
        reference: "https://github.com/YahiaAngelo/Film-Luts",
        license: "MIT repository; individual-LUT rights require review"
    ),
    .init(
        id: "documents-collection",
        label: "Documents LUT collection",
        description: "使用者本機 Documents/luts 收藏；原始作者、下載網址與再散布授權等待使用者補充，不在此階段猜測。",
        reference: nil,
        license: "Pending source-by-source review; do not publish"
    ),
    .init(
        id: "cinecolor",
        label: "CINECOLOR downloaded collection",
        description: "來自 CINECOLOR.IO 的創意調色 LUT；保留原始套件／Look 名稱，輸入色彩空間未由隨附安裝文件明確指定。",
        reference: "https://www.cinecolor.io",
        license: "Downloaded third-party assets; redistribution rights not established; do not publish"
    ),
    .init(
        id: "smallhd-movie-looks-2",
        label: "SmallHD Movie Looks 2",
        description: "SmallHD Movie Looks 2 多相機套件；Look 名稱跨相機重複，Canon、Sony、Panasonic、ARRI 等資料夾作為 Input Profile 證據。",
        reference: nil,
        license: "Downloaded third-party assets; reference and redistribution rights pending"
    ),
    .init(
        id: "filtergrade-film-tone",
        label: "FilterGrade Free Film Tone LUTs",
        description: "FilterGrade 免費 Film Tone 套件；來源由下載資料夾名稱明確標示，Input Profile 未明示。",
        reference: "https://filtergrade.com",
        license: "Downloaded third-party assets; redistribution rights pending"
    ),
    .init(
        id: "filtergrade-free-cine-v2",
        label: "FilterGrade Free Cine LUTs Pack v2",
        description: "FilterGrade Free Cine LUTs Pack v2；隨附支援文件指向 filtergrade.com，重複軟體格式只保留不同 transform。",
        reference: "https://filtergrade.com",
        license: "Downloaded third-party assets; redistribution rights pending"
    ),
    .init(
        id: "premiumbeat-wanderlust",
        label: "PremiumBeat Wanderlust",
        description: "PremiumBeat Wanderlust 17 Free LUTs；隨附授權禁止轉售、轉移、分享或單獨提供原始 LUT。",
        reference: "local package: Wanderlust License and Guide.pdf",
        license: "Local use only for this corpus; do not publish or redistribute"
    ),
    .init(
        id: "print-film-emulation",
        label: "Print Film Emulation LUTs",
        description: "Rec.709 輸入的 Kodak／Fujifilm print-film emulation LUT；品牌由檔名中的底片廠牌判定。",
        reference: nil,
        license: "Downloaded third-party assets; reference and redistribution rights pending"
    ),
    .init(
        id: "cine-luts-free",
        label: "Cine LUTs Free",
        description: "Cine LUTs Free 創意套件；隨附說明僅確認一般剪輯軟體使用方式，未指定 Input Profile 或可再散布授權。",
        reference: nil,
        license: "Downloaded third-party assets; reference and redistribution rights pending"
    ),
    .init(
        id: "freemium-14",
        label: "FREEMIUM 14",
        description: "FREEMIUM 14 創意 LUT 套件；名稱保留原始 Look，來源網址與 Input Profile 待補。",
        reference: nil,
        license: "Downloaded third-party assets; reference and redistribution rights pending"
    ),
    .init(
        id: "free-warm-tone",
        label: "Free Warm Tone LUTs",
        description: "Free Warm Tone LUTs 創意暖調套件；來源網址、Input Profile 與再散布權利待補。",
        reference: nil,
        license: "Downloaded third-party assets; reference and redistribution rights pending"
    ),
    .init(
        id: "super8-footage",
        label: "Free LUTs for Super 8 Footage",
        description: "Super 8 Footage 日光／夜間創意套件；保留底片與時段標籤，Input Profile 未明示。",
        reference: nil,
        license: "Downloaded third-party assets; reference and redistribution rights pending"
    ),
    .init(
        id: "hollywood-lut-color-pack",
        label: "Hollywood LUT Color Pack",
        description: "以電影片名命名的 Hollywood LUT Color Pack；片名視為 Look 參考，不宣稱與片商或原作有官方關係。",
        reference: nil,
        license: "Downloaded third-party assets; reference and redistribution rights pending"
    ),
    .init(
        id: "downloaded-unresolved",
        label: "Downloaded LUT pack (unresolved)",
        description: "下載集合中尚未能由隨附檔案確認製作者的套件；保留原資料夾名稱，不猜測作者、Input Profile 或授權。",
        reference: nil,
        license: "Pending source-by-source review; do not publish"
    ),
]

private func cubeFiles(under root: URL) throws -> [URL] {
    guard FileManager.default.fileExists(atPath: root.path) else { throw CLIError.missingDirectory(root) }
    guard let enumerator = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
    ) else { throw CLIError.missingDirectory(root) }
    var files: [URL] = []
    while let url = enumerator.nextObject() as? URL {
        if url.pathExtension.lowercased() == "cube" { files.append(url) }
    }
    return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
}

private func relative(_ url: URL, to root: URL) -> String {
    let path = url.standardizedFileURL.path
    let prefix = root.standardizedFileURL.path + "/"
    return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : url.lastPathComponent
}

private func cleanPathComponent(_ value: String) -> String {
    value.replacingOccurrences(of: ":", with: "-")
        .replacingOccurrences(of: "/", with: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func semanticTags(path: String, base: [String] = []) -> [String] {
    let value = path.lowercased()
    var tags = Set(base)
    if ["monochrome", "monotone", "acros", "black_white", "black-white", "_bw", "-bw", "/bw/"].contains(where: value.contains) {
        tags.insert("黑白")
    }
    if ["film", "cineon", "kodak", "negative", "print", "2383", "3513"].contains(where: value.contains) {
        tags.insert("底片模擬")
    }
    if value.contains("bleach") { tags.insert("漂白旁路") }
    if ["neutral", "standard", "identity"].contains(where: value.contains) { tags.insert("中性") }
    if ["warm", "sunset", "tungsten"].contains(where: value.contains) { tags.insert("暖調") }
    if ["cool", "winter", "blue_", "blue-"].contains(where: value.contains) { tags.insert("冷調") }
    if ["_to_", "-to-", " to ", "conversion", "aces", "transform"].contains(where: value.contains) {
        tags.insert("技術轉換")
    }
    if tags.isEmpty { tags.insert("創意風格") }
    return tags.sorted()
}

private func brandName(_ raw: String) -> String {
    switch raw.lowercased() {
    case "fuji", "fujifilm": return "Fujifilm"
    case "ricoh": return "RICOH"
    case "sony": return "Sony"
    case "panasonic", "panasonic-standard": return "Panasonic"
    case "arri": return "ARRI"
    case "red": return "RED"
    case "leica": return "Leica"
    case "nikon": return "Nikon"
    case "hasselblad": return "Hasselblad"
    case "canon": return "Canon"
    case "dji": return "DJI"
    case "gopro": return "GoPro"
    case "apple": return "Apple"
    default: return raw
    }
}

/// Highest-confidence Panasonic input evidence lives in the CUBE itself. Read
/// only the header-sized prefix and preserve legacy Latin-1 packages.
private func lumixInputProfile(_ url: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: 32_768) else { return nil }
    let text = String(data: data, encoding: .utf8)
        ?? String(data: data, encoding: .windowsCP1252)
        ?? String(data: data, encoding: .isoLatin1)
    guard let line = text?.split(whereSeparator: \.isNewline).first(where: {
        $0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("#LUMIXPHOTOSTYLE")
    }) else { return nil }
    let pieces = line.split(whereSeparator: \.isWhitespace)
    guard let raw = pieces.last.map(String.init)?.uppercased() else { return nil }
    switch raw {
    case "VLOG": return "Panasonic V-Log"
    case "STD": return "Panasonic STD"
    case "NAT": return "Panasonic NAT"
    default: return "Panasonic \(raw)"
    }
}

private func documentedInputProfile(for url: URL, relativePath: String) -> String {
    if let explicit = lumixInputProfile(url) { return explicit }
    return LUTInputProfileInference.profile(relativePath: relativePath)
}

private func generatedCandidates(
    root: URL, sourceID: String, sourceFolder: String, priority: Int
) throws -> [LUTCorpusCurator.Candidate] {
    var result: [LUTCorpusCurator.Candidate] = []
    let lutsRoot: URL
    let toolsRoot: URL
    if sourceID == "codex-generated" {
        let release = root.appendingPathComponent("releases/vlog-luts.staging", isDirectory: true)
        lutsRoot = release.appendingPathComponent("luts/vlog", isDirectory: true)
        toolsRoot = release.appendingPathComponent("tools", isDirectory: true)
    } else {
        let release = root.appendingPathComponent("out/lumix-s9-vlog", isDirectory: true)
        lutsRoot = release.appendingPathComponent("luts", isDirectory: true)
        toolsRoot = release.appendingPathComponent("tools", isDirectory: true)
    }
    for url in try cubeFiles(under: lutsRoot) {
        let rel = relative(url, to: lutsRoot)
        let components = rel.split(separator: "/").map(String.init)
        guard let rawBrand = components.first else { continue }
        let brand = brandName(rawBrand)
        let rest = components.dropFirst().joined(separator: "/")
        result.append(.init(
            url: url,
            sourceID: sourceID,
            sourcePath: "\(root.lastPathComponent)/\(relative(url, to: root))",
            destinationRelativePath: "\(brand)/\(sourceFolder)/\(rest)",
            brand: brand,
            inputProfile: lumixInputProfile(url) ?? "Panasonic V-Log",
            tags: semanticTags(path: rel, base: ["完成色", "相機風格"]),
            priority: priority
        ))
    }
    for url in try cubeFiles(under: toolsRoot) {
        result.append(.init(
            url: url,
            sourceID: sourceID,
            sourcePath: "\(root.lastPathComponent)/\(relative(url, to: root))",
            destinationRelativePath: "Panasonic/\(sourceFolder)/Technical/\(url.lastPathComponent)",
            brand: "Panasonic",
            inputProfile: lumixInputProfile(url) ?? "Panasonic V-Log",
            tags: semanticTags(path: url.lastPathComponent, base: ["技術轉換", "中性"]),
            priority: priority
        ))
    }
    return result
}

private func filmCandidates(root: URL) throws -> [LUTCorpusCurator.Candidate] {
    let luts = root.appendingPathComponent("luts", isDirectory: true)
    return try cubeFiles(under: luts).map { url in
        let rel = relative(url, to: luts)
        return .init(
            url: url,
            sourceID: "gmic-film-luts",
            sourcePath: "Film-Luts/luts/\(rel)",
            destinationRelativePath: "G-MIC Film LUTs/Film-Luts/\(rel)",
            brand: "G'MIC Film LUTs",
            inputProfile: "Display / Rec.709",
            tags: semanticTags(path: rel, base: ["底片模擬"]),
            priority: 30
        )
    }
}

private func alchemyCandidates(root: URL) throws -> [LUTCorpusCurator.Candidate] {
    let luts = root.appendingPathComponent("Luts", isDirectory: true)
    return try cubeFiles(under: luts).compactMap { url in
        let rel = relative(url, to: luts)
        let components = rel.split(separator: "/").map(String.init)
        guard let first = components.first, first.caseInsensitiveCompare("Archive") != .orderedSame else {
            return nil
        }
        let brand = first.caseInsensitiveCompare("Cineon") == .orderedSame
            ? "Film Emulation" : brandName(first)
        return .init(
            url: url,
            sourceID: "vlog-alchemy",
            sourcePath: "V-Log-Alchemy/Luts/\(rel)",
            destinationRelativePath: "\(brand)/V-Log Alchemy/\(rel)",
            brand: brand,
            inputProfile: lumixInputProfile(url) ?? "Panasonic V-Log",
            tags: semanticTags(path: rel, base: ["完成色", "相機風格"]),
            priority: 20
        )
    }
}

private let directDocumentBrands: Set<String> = [
    "Fujifilm", "Sony", "Canon", "Panasonic", "DJI", "Nikon", "GoPro", "Leica", "Apple",
]

private func documentPlacement(_ relativePath: String) -> (brand: String, remainder: String) {
    let components = relativePath.split(separator: "/").map(String.init)
    guard let first = components.first else { return ("Unclassified", relativePath) }
    if directDocumentBrands.contains(first) {
        return (brandName(first), components.dropFirst().joined(separator: "/"))
    }
    if first.caseInsensitiveCompare("freshluts.com") == .orderedSame {
        return ("FreshLUTs", components.dropFirst().joined(separator: "/"))
    }
    if first == "DaVinci Resolve", components.count > 1 {
        let explicit: [String: String] = [
            "Blackmagic Design": "Blackmagic Design", "RED": "RED",
            "Olympus": "Olympus", "Astrodesign": "Astrodesign",
        ]
        if let brand = explicit[components[1]] {
            return (brand, relativePath)
        }
        return ("DaVinci Resolve", components.dropFirst().joined(separator: "/"))
    }
    return (brandName(first), components.dropFirst().joined(separator: "/"))
}

private func documentCandidates(root: URL) throws -> [LUTCorpusCurator.Candidate] {
    let collection = root.appendingPathComponent("test", isDirectory: true)
    return try cubeFiles(under: collection).map { url in
        let rel = relative(url, to: collection)
        let placement = documentPlacement(rel)
        let remainder = placement.remainder.isEmpty ? url.lastPathComponent : placement.remainder
        return .init(
            url: url,
            sourceID: "documents-collection",
            sourcePath: "Documents/luts/test/\(rel)",
            destinationRelativePath: "\(cleanPathComponent(placement.brand))/Documents Collection/\(remainder)",
            brand: placement.brand,
            inputProfile: documentedInputProfile(for: url, relativePath: rel),
            tags: semanticTags(path: rel),
            priority: 40
        )
    }
}

private func downloadedCandidates(root: URL) throws -> [LUTCorpusCurator.Candidate] {
    try cubeFiles(under: root).map { url in
        let rel = relative(url, to: root)
        let classification = DownloadedLUTClassifier.classify(relativePath: rel)
        return .init(
            url: url,
            sourceID: classification.sourceID,
            sourcePath: "Downloaded Luts/lut unzip/\(rel)",
            destinationRelativePath: "\(cleanPathComponent(classification.brand))/\(cleanPathComponent(classification.sourceFolder))/\(classification.destinationSubpath)",
            brand: classification.brand,
            inputProfile: classification.inputProfile,
            tags: classification.tags,
            priority: 50
        )
    }
}

do {
    let arguments = try Arguments(CommandLine.arguments)
    if let root = arguments.verify {
        let result = try LUTCorpusCurator.verify(outputRoot: root)
        print("Verified \(result.active) active LUTs")
        for (profile, count) in result.profiles.sorted(by: { $0.key < $1.key }) {
            print("\(profile): \(count)")
        }
        exit(0)
    }
    for root in [
        arguments.film, arguments.codex, arguments.claude,
        arguments.alchemy, arguments.documents, arguments.downloads,
    ]
        where FileManager.default.fileExists(atPath: root.path) == false {
        throw CLIError.missingDirectory(root)
    }

    var candidates: [LUTCorpusCurator.Candidate] = []
    candidates += try generatedCandidates(
        root: arguments.codex,
        sourceID: "codex-generated", sourceFolder: "Codex Generated", priority: 0
    )
    candidates += try generatedCandidates(
        root: arguments.claude,
        sourceID: "claude-generated", sourceFolder: "Claude Generated", priority: 10
    )
    candidates += try alchemyCandidates(root: arguments.alchemy)
    candidates += try filmCandidates(root: arguments.film)
    candidates += try documentCandidates(root: arguments.documents)
    candidates += try downloadedCandidates(root: arguments.downloads)

    print("Curating \(candidates.count) canonical candidates into \(arguments.output.path)…")
    let result = try LUTCorpusCurator.curate(
        sources: sources, candidates: candidates, outputRoot: arguments.output
    )
    print("Active: \(result.active); duplicates: \(result.duplicates); unsupported: \(result.unsupported)")
} catch {
    FileHandle.standardError.write(Data("lutcurate: \(error.localizedDescription)\n".utf8))
    exit(1)
}
