import Foundation

/// A `major.minor.patch` version, as found in `CFBundleShortVersionString` and in a release tag.
///
/// Accepts a leading `v` because GitHub tags carry one (`v0.1.0`) and Info.plist does not (`0.1.0`).
/// Anything after the third component, or a pre-release suffix, is rejected rather than guessed at:
/// the release script only ever produces plain triples, so a tag that does not parse is a tag the
/// updater should ignore, not one it should half-understand.
struct AppVersion: Sendable, Equatable, Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init?(_ string: String) {
        var text = Substring(string.trimmingCharacters(in: .whitespaces))
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let n = Int(part) else { return nil }
            numbers.append(n)
        }
        while numbers.count < 3 { numbers.append(0) }
        self.init(numbers[0], numbers[1], numbers[2])
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var description: String { "\(major).\(minor).\(patch)" }

    /// The version of the running app, or `nil` for a bare SwiftPM executable, which has no
    /// Info.plist. Updates are a property of the packaged app; `swift run` has nothing to update.
    static var current: AppVersion? {
        guard let string = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return nil }
        return AppVersion(string)
    }
}
