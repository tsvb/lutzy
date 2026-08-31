import XCTest
@testable import LUTzyKit

/// `docs/PHASE2_SPEC.md` §5's **derive baseline immunity** invariant: `RecipeExtractor` must never
/// receive `document.rawDevelop`. A derived cube is fit against the *neutral* RAW render, so if a
/// user's develop settings ever reached `derive`, the cube would absorb them and then be applied on
/// top of them — the correction would land twice.
///
/// **The spec claimed this was "enforced by construction plus a test that fails if the derive
/// signature gains a develop parameter". No such test existed.** `RecipeExtractor.derive` was
/// referenced exactly once in the whole test target, as a plain call inside a lazy fixture; nothing
/// looked at its signature. The named candidate, `DeriveInvarianceTests`, pins the *pipeline's*
/// develop wiring and is invariant to derive's parameter list — and it skips wholesale without a
/// local DNG, so on CI and on a clean clone it asserts nothing at all. Appending
/// `develop: RAWDevelopSettings = .neutral` to `derive` and threading it from both call sites left
/// the entire suite green. This file is that missing test.
///
/// **It reads source text, and that is deliberate** — the same reasoning as `RenderStackTests`. The
/// invariant is about what `derive` *can be handed*, and a defaulted parameter that nobody passes
/// yet has no runtime trace whatsoever: `RAWDevelopSettings.neutral` renders byte-identically to
/// `ImageDecoder.developRAWNeutral`, so even with a real DNG the derived cube is bit-identical.
/// There is no pixel to assert on. The only way to catch the parameter is to look for it.
///
/// Costs no fixture and needs no DNG, so unlike every other derive test it actually runs on CI.
final class DeriveBaselineImmunityTests: XCTestCase {

    /// The package root, found relative to this file rather than to the working directory —
    /// `swift test` and Xcode disagree about the latter.
    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)      // Tests/LUTzyKitTests/DeriveBaselineImmunityTests.swift
            .deletingLastPathComponent()      // Tests/LUTzyKitTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // package root
    }

    /// The derive path: the extractor itself, and the only view model that drives it.
    private static let derivePath = [
        "Sources/LUTzyKit/Models/RecipeExtractor.swift",
        "Sources/LUTzyKit/ViewModels/DeriveCoordinator.swift",
    ]

    /// A file's source with comments removed, so that prose *about* develop settings does not read
    /// as a reference to them. Both `//`-prefixed lines and `/* … */` blocks are stripped.
    ///
    /// Only whole comment lines are dropped, never a trailing `//` on a line of code: a URL scheme
    /// in a string literal (`"derived://…"`) contains `//` too, and stripping from the first `//`
    /// anywhere would silently eat real code. `RenderStackTests` and `PackageSettingsTests` both
    /// take the same conservative approach; this one additionally handles block comments, which
    /// they do not.
    private func code(at relativePath: String) throws -> String {
        let url = Self.packageRoot.appendingPathComponent(relativePath)
        var text = try String(contentsOf: url, encoding: .utf8)

        while let open = text.range(of: "/*") {
            guard let close = text.range(of: "*/", range: open.upperBound..<text.endIndex) else {
                text = String(text[text.startIndex..<open.lowerBound])
                break
            }
            text.replaceSubrange(open.lowerBound..<close.upperBound, with: "")
        }

        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// The declared parameter labels of `RecipeExtractor.derive`, read out of the source.
    private func deriveParameterLabels() throws -> [String] {
        let source = try code(at: "Sources/LUTzyKit/Models/RecipeExtractor.swift")
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        guard let start = lines.firstIndex(where: { $0.contains("static func derive(") }) else {
            XCTFail("could not find `static func derive(` in RecipeExtractor.swift — if it was "
                    + "renamed or reformatted, update this test deliberately rather than deleting it")
            return []
        }

        var labels: [String] = []
        for line in lines[(start + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(")") { return labels }          // end of the parameter list
            labels.append(contentsOf: Self.parameterLabels(in: trimmed))
        }

        XCTFail("never found the end of derive's parameter list — the declaration did not parse")
        return []
    }

    /// Every parameter label on one line of a declaration.
    ///
    /// **Reads every parameter on the line, not just the first.** It read only the first until the
    /// second opposition pass, which is a hole precisely the shape of the defect this file exists to
    /// catch: appending `, exposureBias: Double = 0` to the end of an existing parameter's line left
    /// the parsed set unchanged at five labels, and the exact-set assertion passed with a sixth
    /// parameter present. The sibling test would not have caught it either — it blacklists
    /// `EditDocument`, `RAWDevelopSettings` and `rawDevelop`, and a develop knob typed as `Double`
    /// names none of them.
    ///
    /// Splitting is depth-aware because a parameter type contains commas of its own:
    /// `progress: ((Double, String) -> Void)? = nil` is one parameter, not three. Only `(` and `[`
    /// open a level — angle brackets are deliberately ignored, since `->` would otherwise read as a
    /// closing bracket. A generic parameter type with a top-level comma (`Dictionary<String, Int>`)
    /// would therefore split wrongly and fail the assertion; that is the safe direction to be wrong
    /// in, because it fails loudly rather than passing quietly.
    private static func parameterLabels(in line: String) -> [String] {
        var fragments: [String] = []
        var current = ""
        var depth = 0
        for ch in line {
            switch ch {
            case "(", "[":
                depth += 1
                current.append(ch)
            case ")", "]":
                depth -= 1
                current.append(ch)
            case "," where depth == 0:
                fragments.append(current)
                current = ""
            default:
                current.append(ch)
            }
        }
        fragments.append(current)

        return fragments.compactMap { fragment in
            guard let colon = fragment.firstIndex(of: ":") else { return nil }
            let label = fragment[fragment.startIndex..<colon]
                .trimmingCharacters(in: .whitespaces)
                .split(separator: " ").first.map(String.init) ?? ""
            return label.isEmpty ? nil : label
        }
    }

    /// The invariant the spec said was covered: **derive's signature cannot gain a develop parameter.**
    ///
    /// Asserted as an exact set rather than an absence, so that *any* new parameter has to be
    /// considered here — a develop knob under a name this test never thought to blacklist
    /// (`settings:`, `raw:`, `baseline:`) fails just the same, and so does one packed onto the same
    /// line as an existing parameter, which slipped through until `parameterLabels(in:)` learned to
    /// read past the first label on a line.
    func testDeriveSignatureTakesOnlyURLsOptionsAndCallbacks() throws {
        let labels = try deriveParameterLabels()

        XCTAssertFalse(
            labels.isEmpty,
            "read no parameters at all — this test would pass vacuously, which is exactly the "
                + "failure mode it exists to correct"
        )

        XCTAssertEqual(
            Set(labels),
            ["rawURL", "jpgURL", "options", "progress", "isCancelled"],
            """
            RecipeExtractor.derive's parameter list changed. Derive fits its cube against the \
            NEUTRAL raw render (PHASE2_SPEC §5, "derive baseline immunity"): if a develop setting \
            reaches it, the cube absorbs the correction and the pipeline then applies it again on \
            top. A defaulted parameter is not safe here — it compiles at every call site and \
            renders identically until someone passes it. Found: \(labels.sorted()).
            """
        )
    }

    /// The construction half of the invariant, which the spec described as "no `EditDocument`
    /// import". There is no import to omit — `EditDocument` and `RecipeExtractor` are the same
    /// module — so the real barrier is that the derive path never *names* the document or its
    /// develop settings. That is a convention, and this is what holds it.
    func testTheDerivePathNeverNamesTheDocumentOrItsDevelopSettings() throws {
        for path in Self.derivePath {
            let source = try code(at: path)

            XCTAssertGreaterThan(source.count, 500,
                                 "\(path) read as \(source.count) chars — the file moved or the "
                                     + "comment stripper ate it, and this check is not running")

            for symbol in ["EditDocument", "RAWDevelopSettings", "rawDevelop"] {
                XCTAssertFalse(
                    source.contains(symbol),
                    """
                    \(symbol) appears in \(path). The derive path is required to be independent of \
                    the edit document and of any user develop settings (PHASE2_SPEC §5). If derive \
                    genuinely needs to know about them, that is a spec change — raise it rather \
                    than deleting this assertion.
                    """
                )
            }
        }
    }

    /// The positive half: derive must still go through the one neutral decode it is allowed to use.
    /// Without this, the test above is satisfiable by deleting the RAW decode entirely.
    func testDeriveStillDecodesThroughTheNeutralBaseline() throws {
        let source = try code(at: "Sources/LUTzyKit/Models/RecipeExtractor.swift")
        XCTAssertTrue(
            source.contains("ImageDecoder.developRAWNeutral"),
            "derive should read its RAW through ImageDecoder.developRAWNeutral — the neutral "
                + "baseline it is fit against"
        )
    }
}
