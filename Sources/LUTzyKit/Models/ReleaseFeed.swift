import Foundation

/// One published release, reduced to what the updater needs.
struct Release: Sendable, Equatable {
    let version: AppVersion
    let title: String
    /// The release notes, as GitHub-flavoured Markdown.
    let notes: String
    /// The release page, for a build that cannot install itself.
    let pageURL: URL
    /// The disk image to install from, if the release carries one.
    let diskImageURL: URL?
    let diskImageSize: Int?
}

/// Where releases come from: the GitHub Releases API for this repository.
///
/// `releases/latest` is the newest non-draft, non-prerelease release, which is exactly the set
/// `scripts/release-dmg.sh` output is published to. The DMG asset is found by extension, so the
/// asset name can change without a code change; a release with no DMG is still reported, and the
/// sheet offers the release page instead of an install.
enum ReleaseFeed {

    static let repository = "tsvb/lutzy"

    static func latestURL(repository: String = repository) -> URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    enum FeedError: LocalizedError, Equatable {
        case badStatus(Int)
        case unusableTag(String)

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): return "GitHub answered with status \(code)."
            case .unusableTag(let tag): return "The latest release is tagged \"\(tag)\", which is not a version."
            }
        }
    }

    /// Fetch and decode the latest release. Unauthenticated: sixty requests an hour is plenty for
    /// one check a day plus a few manual ones.
    static func fetchLatest(
        repository: String = repository,
        session: URLSession = .shared
    ) async throws -> Release {
        var request = URLRequest(url: latestURL(repository: repository))
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("LUTzy/\(AppVersion.current?.description ?? "dev")", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FeedError.badStatus(http.statusCode)
        }
        return try parse(data)
    }

    // MARK: - Decoding

    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
            let size: Int?
        }
        let tag_name: String
        let name: String?
        let body: String?
        let html_url: URL
        let assets: [Asset]?
    }

    /// Decode a `releases/latest` body. Internal so the decoder can be tested on a fixture without
    /// a network.
    static func parse(_ data: Data) throws -> Release {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let version = AppVersion(payload.tag_name) else {
            throw FeedError.unusableTag(payload.tag_name)
        }
        let dmg = payload.assets?.first { $0.name.lowercased().hasSuffix(".dmg") }
        return Release(
            version: version,
            title: payload.name?.isEmpty == false ? payload.name! : "LUTzy \(version)",
            notes: payload.body ?? "",
            pageURL: payload.html_url,
            diskImageURL: dmg?.browser_download_url,
            diskImageSize: dmg?.size
        )
    }
}
