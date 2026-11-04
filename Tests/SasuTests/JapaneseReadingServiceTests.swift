import XCTest
@testable import Sasu

final class JapaneseReadingServiceTests: XCTestCase {
    func testModelReadingsAreAcceptedWhenTheyRebuildTheSource() throws {
        let response = """
        {"segments":[{"text":"土曜日","reading":"どようび"},{"text":"に","reading":null},{"text":"行","reading":"い"},{"text":"きます。","reading":null}]}
        """

        let segments = try XCTUnwrap(
            AIRequestSupport.parseJapaneseReadings(from: response, sourceText: "土曜日に行きます。")
        )

        XCTAssertEqual(segments, [
            RubyTextSegment(text: "土曜日", reading: "どようび"),
            RubyTextSegment(text: "に", reading: nil),
            RubyTextSegment(text: "行", reading: "い"),
            RubyTextSegment(text: "きます。", reading: nil)
        ])
    }

    func testModelReadingsInsideACodeFenceAreAccepted() {
        let response = """
        ```json
        {"segments":[{"text":"日本","reading":"にほん"}]}
        ```
        """

        XCTAssertNotNil(AIRequestSupport.parseJapaneseReadings(from: response, sourceText: "日本"))
    }

    func testModelReadingsThatChangeTheSourceAreRejected() {
        let response = """
        {"segments":[{"text":"土曜日","reading":"どようび"},{"text":"に行きます","reading":null}]}
        """

        XCTAssertNil(AIRequestSupport.parseJapaneseReadings(from: response, sourceText: "土曜日に行きます。"))
    }

    func testModelReadingsThatAreNotHiraganaAreRejected() {
        let response = """
        {"segments":[{"text":"土曜日","reading":"doyoubi"}]}
        """

        XCTAssertNil(AIRequestSupport.parseJapaneseReadings(from: response, sourceText: "土曜日"))
    }

    func testReadingsOnKanaSegmentsAreDropped() throws {
        let response = """
        {"segments":[{"text":"東京","reading":"とうきょう"},{"text":"へ","reading":"え"}]}
        """

        let segments = try XCTUnwrap(
            AIRequestSupport.parseJapaneseReadings(from: response, sourceText: "東京へ")
        )
        XCTAssertEqual(segments.last, RubyTextSegment(text: "へ", reading: nil))
    }

    func testKanjiDetectionGatesTheReadingsRequest() {
        XCTAssertTrue(JapaneseReadingService.containsKanji("土曜日に行きます"))
        XCTAssertFalse(JapaneseReadingService.containsKanji("ありがとう、サス"))
    }

    func testMalformedModelOutputIsRejected() {
        XCTAssertNil(AIRequestSupport.parseJapaneseReadings(from: "どようび", sourceText: "土曜日"))
    }
}
