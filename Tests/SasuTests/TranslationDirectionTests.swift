import XCTest
@testable import Sasu

final class TranslationDirectionTests: XCTestCase {
    func testJapaneseInterfacePrefersEnglishToJapaneseTranslation() {
        let direction = TranslationDirection.forPreferredLanguages(["ja-JP", "en-US"])

        XCTAssertEqual(direction.expectedSourceLanguage, "English")
        XCTAssertEqual(direction.targetLanguage, "Japanese")
    }

    func testEnglishInterfacePrefersJapaneseToEnglishTranslation() {
        let direction = TranslationDirection.forPreferredLanguages(["en-US", "ja-JP"])

        XCTAssertEqual(direction.expectedSourceLanguage, "Japanese")
        XCTAssertEqual(direction.targetLanguage, "English")
    }

    func testOnlyFirstPreferredLanguageControlsInterfaceLanguage() {
        XCTAssertTrue(TranslationDirection.prefersJapaneseInterface(for: ["ja-JP", "en-US"]))
        XCTAssertFalse(TranslationDirection.prefersJapaneseInterface(for: ["en-US", "ja-JP"]))
        XCTAssertFalse(TranslationDirection.prefersJapaneseInterface(for: []))
    }

    func testJapaneseInterfaceRequestsJapaneseScreenshotAnswers() {
        let instructions = TranslationDirection.screenshotLanguageBehaviorInstructions(
            for: ["ja-JP", "en-US"]
        )

        XCTAssertTrue(instructions.contains("Always answer in Japanese"))
        XCTAssertTrue(instructions.contains("target label in Japanese"))
        XCTAssertFalse(instructions.contains("Always answer in English"))
    }
}
