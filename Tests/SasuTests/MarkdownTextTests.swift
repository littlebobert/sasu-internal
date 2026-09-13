import AppKit
import XCTest
@testable import Sasu

final class MarkdownTextTests: XCTestCase {
    func testMixedJapaneseSearchQueryUsesFallbackFontsWithoutLosingText() throws {
        let markdown = #"("イオンモール成田" OR "成田イオン") (デロリアン OR デロリアン乗車撮影会) since:2026-09-13"#
        let renderedText = attributedMarkdownText(markdown, fontSize: 13)

        XCTAssertEqual(renderedText.string, markdown)

        let japaneseRange = (renderedText.string as NSString).range(of: "イオンモール成田")
        let japaneseFont = try XCTUnwrap(
            renderedText.attribute(.font, at: japaneseRange.location, effectiveRange: nil) as? NSFont
        )
        let latinRange = (renderedText.string as NSString).range(of: "since")
        let latinFont = try XCTUnwrap(
            renderedText.attribute(.font, at: latinRange.location, effectiveRange: nil) as? NSFont
        )

        XCTAssertNotEqual(japaneseFont.fontName, NSFont.systemFont(ofSize: 13).fontName)
        XCTAssertEqual(latinFont.fontName, NSFont.systemFont(ofSize: 13).fontName)
    }
}
