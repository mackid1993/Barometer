import AppKit
import Testing
@testable import MenuBarStatsUI

@Suite("Release notes formatting")
struct ReleaseNotesFormatterTests {
    @Test("Markdown blocks become distinct native text paragraphs")
    func rendersBlocks() {
        let source = """
        # Barometer 1.0.3

        A **faster** update with [details](https://example.com).

        - Lower background use
        - Smoother scrolling
        """

        let result = ReleaseNotesFormatter.attributedString(markdown: source)

        #expect(result.string == "Barometer 1.0.3\nA faster update with details.\n•\tLower background use\n•\tSmoother scrolling\n")
        #expect(!result.string.contains("**"))
        #expect(!result.string.contains("[details]"))
        #expect(result.attribute(.link, at: 40, effectiveRange: nil) as? URL == URL(string: "https://example.com"))
    }

    @Test("Hard-wrapped Markdown remains one paragraph")
    func joinsSoftWrappedLines() {
        let source = """
        This paragraph is wrapped in the release file,
        but it should flow with the width of the update window.
        """

        let result = ReleaseNotesFormatter.attributedString(markdown: source)

        #expect(result.string == "This paragraph is wrapped in the release file, but it should flow with the width of the update window.\n")
    }

    @Test("Large release notes remain a bounded native document")
    func rendersLargeDocument() {
        let source = (1...500).map { "- Change **\($0)**" }.joined(separator: "\n")

        let result = ReleaseNotesFormatter.attributedString(markdown: source)

        #expect(result.string.components(separatedBy: "\n").count == 501)
        #expect(result.length < 10_000)
    }
}
