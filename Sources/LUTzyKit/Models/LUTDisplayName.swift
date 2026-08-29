import Foundation

/// Produces a readable library label without renaming or modifying the LUT file.
/// User-authored catalog names bypass this normalizer entirely.
enum LUTDisplayName {
    private static let cameraSuffix = try! NSRegularExpression(
        pattern: #"\.[ACP]\d{3,}(?:[_ ]\d{5,})?(?:[_ ][A-Z]\d*)?$"#
    )
    private static let leadingCounter = try! NSRegularExpression(
        pattern: #"^(?:\d|0\d)_+(?=[^\d_])"#
    )
    private static let numericOnly = try! NSRegularExpression(
        pattern: #"^\d+(?:[ .-]\d+)*$"#
    )
    private static let collectionSuffix = try! NSRegularExpression(
        pattern: #"(?i)\s+(?:LUT\s+)?collection$"#
    )
    private static let whitespace = try! NSRegularExpression(pattern: #"\s+"#)

    static func normalized(
        _ filenameDerivedName: String,
        brand: String? = nil,
        source: String? = nil
    ) -> String {
        let original = filenameDerivedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard original.isEmpty == false else { return filenameDerivedName }

        var value = original

        // Camera and asset-manager exports commonly append clip IDs such as
        // `.A049_12291747_S` or `20.C0021`. They identify the source file, not
        // the look, and make otherwise useful names impossible to scan.
        value = replacing(cameraSuffix, in: value, with: "")

        // A single digit or zero-padded two-digit prefix joined with an
        // underscore is strong evidence of an export/list counter. Do this
        // before turning underscores into spaces so real titles such as
        // "12 Years a Slave" keep their meaningful number.
        value = replacing(leadingCounter, in: value, with: "")
        value = value.replacingOccurrences(of: "_", with: " ")
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "-_. "))
        value = collapseWhitespace(value)

        if firstMatch(numericOnly, in: value) != nil {
            let qualifier = usefulQualifier(brand) ?? usefulQualifier(source)
            // An underscore-separated camera sequence such as `1_25` is a
            // list index, while a dotted value such as `1.2` is a meaningful
            // version. Preserve the latter so distinct looks do not collide.
            let sequenceNumber = value.contains(" ")
                ? value.split(separator: " ").first.map(String.init) ?? value
                : value
            return [qualifier, "Look", sequenceNumber].compactMap { $0 }.joined(separator: " ")
        }

        return value.isEmpty ? original : value
    }

    private static func usefulQualifier(_ candidate: String?) -> String? {
        guard var candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              candidate.isEmpty == false,
              candidate.caseInsensitiveCompare("Unknown") != .orderedSame,
              candidate.caseInsensitiveCompare("Custom") != .orderedSame
        else { return nil }

        candidate = replacing(collectionSuffix, in: candidate, with: "")
        candidate = collapseWhitespace(candidate)
        return candidate.isEmpty ? nil : candidate
    }

    private static func collapseWhitespace(_ value: String) -> String {
        replacing(whitespace, in: value, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacing(
        _ regex: NSRegularExpression, in value: String, with replacement: String
    ) -> String {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
    }

    private static func firstMatch(_ regex: NSRegularExpression, in value: String) -> NSTextCheckingResult? {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range)
    }
}
