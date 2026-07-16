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

    func testTaiwanInterfacePrefersJapaneseToTraditionalChineseTranslation() {
        for locale in ["zh-Hant-TW", "zh-TW", "zh_TW"] {
            let direction = TranslationDirection.forPreferredLanguages([locale, "en-US"])

            XCTAssertEqual(direction.expectedSourceLanguage, "Japanese")
            XCTAssertEqual(direction.targetLanguage, "Traditional Chinese")
            XCTAssertTrue(TranslationDirection.prefersTraditionalChineseInterface(for: [locale]))
        }
    }

    func testMainlandChinaInterfacePrefersJapaneseToSimplifiedChineseTranslation() {
        for locale in ["zh-Hans-CN", "zh-CN", "zh_CN"] {
            let direction = TranslationDirection.forPreferredLanguages([locale, "en-US"])

            XCTAssertEqual(direction.expectedSourceLanguage, "Japanese")
            XCTAssertEqual(direction.targetLanguage, "Simplified Chinese")
            XCTAssertTrue(TranslationDirection.prefersSimplifiedChineseInterface(for: [locale]))
            XCTAssertFalse(TranslationDirection.prefersTraditionalChineseInterface(for: [locale]))
        }
    }

    func testTraditionalChineseLanguagePairsCanBeSelectedExplicitly() {
        let japaneseDirection = TranslationDirection.forPreferredLanguages(
            ["en-US"],
            languagePair: .traditionalChineseJapanese
        )
        let englishDirection = TranslationDirection.forPreferredLanguages(
            ["ja-JP"],
            languagePair: .traditionalChineseEnglish
        )

        XCTAssertEqual(japaneseDirection.expectedSourceLanguage, "Japanese")
        XCTAssertEqual(japaneseDirection.targetLanguage, "Traditional Chinese")
        XCTAssertEqual(englishDirection.expectedSourceLanguage, "English")
        XCTAssertEqual(englishDirection.targetLanguage, "Traditional Chinese")
    }

    func testSimplifiedChineseLanguagePairsCanBeSelectedExplicitly() {
        let japaneseDirection = TranslationDirection.forPreferredLanguages(
            ["en-US"],
            languagePair: .simplifiedChineseJapanese
        )
        let englishDirection = TranslationDirection.forPreferredLanguages(
            ["ja-JP"],
            languagePair: .simplifiedChineseEnglish
        )

        XCTAssertEqual(japaneseDirection.expectedSourceLanguage, "Japanese")
        XCTAssertEqual(japaneseDirection.targetLanguage, "Simplified Chinese")
        XCTAssertEqual(englishDirection.expectedSourceLanguage, "English")
        XCTAssertEqual(englishDirection.targetLanguage, "Simplified Chinese")
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

    func testTraditionalChineseInterfaceRequestsTraditionalChineseScreenshotAnswers() {
        let instructions = TranslationDirection.screenshotLanguageBehaviorInstructions(
            for: ["zh-Hant-TW", "en-US"]
        )

        XCTAssertTrue(instructions.contains("Always answer in Traditional Chinese"))
        XCTAssertTrue(instructions.contains("target label in Traditional Chinese"))
    }

    func testSimplifiedChineseInterfaceRequestsSimplifiedChineseScreenshotAnswers() {
        let instructions = TranslationDirection.screenshotLanguageBehaviorInstructions(
            for: ["zh-Hans-CN", "en-US"]
        )

        XCTAssertTrue(instructions.contains("Always answer in Simplified Chinese"))
        XCTAssertTrue(instructions.contains("target label in Simplified Chinese"))
    }
}
