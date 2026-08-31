import XCTest
@testable import LUTzyKit

/// **A test named in the live docs has to exist.**
///
/// This exists because of the way `PHASE2_SPEC.md` §5 lied for seven steps. Its derive-immunity
/// invariant said it was enforced "plus a test that fails if the derive signature gains a develop
/// parameter", and no such test had ever been written. The sentence was reviewed repeatedly and read
/// as a record every time, because a claim about coverage *sounds* like a claim about the past.
///
/// The rule that makes that class of drift mechanically checkable is: **a doc sentence that claims a
/// test exists must name it.** Once it is named, this file checks it. An unnamed promise is
/// unverifiable by anything but a human who goes looking, and the history of this repo is that nobody
/// does — so prefer `` `DeriveBaselineImmunityTests` `` over "a test".
///
/// Two failure modes are caught: a test that was never written, and one that was renamed out from
/// under a doc that still cites the old name. Both are silent today.
///
/// **Scope: the four documents that describe HEAD** — `PHASE2_SPEC.md`, `CODE_REVIEW.md`, `CLAUDE.md`
/// and `README.md`. `docs/superpowers/` is deliberately excluded: those are plan and design documents
/// archived as they were written, and 13 of the test names in them drifted during implementation.
/// That is not rot — a plan is a record of what was planned, and the step10a design doc already says
/// so in as many words ("As built, the names drifted and one row split"). Rewriting them to match
/// HEAD would destroy the only evidence of what changed between plan and build. They are history;
/// these four are claims.
final class DocumentedTestNamesTests: XCTestCase {

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)      // Tests/LUTzyKitTests/DocumentedTestNamesTests.swift
            .deletingLastPathComponent()      // Tests/LUTzyKitTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // package root
    }

    /// The documents that are supposed to be true of HEAD. See the note above on `docs/superpowers/`.
    private static let liveDocs = [
        "docs/PHASE2_SPEC.md",
        "docs/CODE_REVIEW.md",
        "CLAUDE.md",
        "README.md",
    ]

    /// `LUTzyKitTests` is the test *target* — it appears in every path in every doc, and is not a suite.
    private static let notASuite: Set<String> = ["LUTzyKitTests"]

    private func matches(_ pattern: String, in text: String, group: Int = 0) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: group), in: text).map { String(text[$0]) }
        }
    }

    private func testTargetSource() throws -> String {
        let dir = Self.packageRoot.appendingPathComponent("Tests/LUTzyKitTests")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 20, "expected to scan the whole test target, found \(files.count) files")
        return try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }

    /// Every `testSomething` named in a live doc is a real test function.
    func testEveryTestNamedInTheLiveDocsExists() throws {
        let source = try testTargetSource()
        let defined = Set(matches(#"func (test[A-Za-z0-9_]*)"#, in: source, group: 1))
        XCTAssertGreaterThan(defined.count, 200, "found only \(defined.count) test functions — the scan is not working")

        var referenced = 0
        var missing: [String] = []

        for doc in Self.liveDocs {
            let text = try String(contentsOf: Self.packageRoot.appendingPathComponent(doc), encoding: .utf8)
            for name in Set(matches(#"(?<![A-Za-z0-9_])test[A-Z][A-Za-z0-9_]*"#, in: text)) {
                referenced += 1
                if !defined.contains(name) { missing.append("\(doc) cites \(name)") }
            }
        }

        XCTAssertGreaterThan(referenced, 0,
                             "no test names found in any live doc — the regex or the file list is wrong, "
                                 + "and this check would pass vacuously")

        XCTAssertEqual(
            missing, [],
            """
            A document that describes HEAD names a test that does not exist. Either the test was \
            renamed and the doc was not updated, or the doc claims coverage that was never written — \
            the second is what PHASE2_SPEC §5's derive-immunity invariant did for seven steps. Fix \
            the doc, or write the test; do not delete this assertion.
            """
        )
    }

    /// Every `SomethingTests` suite named in a live doc is a real test class.
    func testEverySuiteNamedInTheLiveDocsExists() throws {
        let source = try testTargetSource()
        let defined = Set(matches(#"class ([A-Za-z0-9_]+) *:"#, in: source, group: 1))
        XCTAssertGreaterThan(defined.count, 10, "found only \(defined.count) test classes — the scan is not working")

        var missing: [String] = []
        for doc in Self.liveDocs {
            let text = try String(contentsOf: Self.packageRoot.appendingPathComponent(doc), encoding: .utf8)
            let cited = Set(matches(#"(?<![A-Za-z0-9_])[A-Z][A-Za-z0-9_]*Tests(?![A-Za-z0-9_])"#, in: text))
            for name in cited.subtracting(Self.notASuite) where !defined.contains(name) {
                missing.append("\(doc) cites \(name)")
            }
        }

        XCTAssertEqual(missing, [], "a live document names a test suite that does not exist")
    }
}
