import XCTest
@testable import Sasu

final class TranslationDirectionTests: XCTestCase {
    func testJapaneseIsDefaultSourceRegardlessOfInterfaceLanguage() {
        let japaneseInterface = TranslationDirection.forPreferredLanguages(["ja-JP", "en-US"])
        let englishInterface = TranslationDirection.forPreferredLanguages(["en-US", "ja-JP"])

        XCTAssertEqual(japaneseInterface.expectedSourceLanguage, "Japanese")
        XCTAssertEqual(japaneseInterface.targetLanguage, "English")
        XCTAssertEqual(englishInterface.expectedSourceLanguage, "Japanese")
        XCTAssertEqual(englishInterface.targetLanguage, "English")
    }

    func testTaiwanInterfaceTranslatesJapaneseToTraditionalChinese() {
        for locale in ["zh-Hant-TW", "zh-TW", "zh_TW"] {
            let direction = TranslationDirection.forPreferredLanguages([locale, "en-US"])

            XCTAssertEqual(direction.expectedSourceLanguage, "Japanese")
            XCTAssertEqual(direction.targetLanguage, "Traditional Chinese")
            XCTAssertTrue(TranslationDirection.prefersTraditionalChineseInterface(for: [locale]))
        }
    }

    func testMainlandChinaInterfaceTranslatesJapaneseToSimplifiedChinese() {
        for locale in ["zh-Hans-CN", "zh-CN", "zh_CN"] {
            let direction = TranslationDirection.forPreferredLanguages([locale, "en-US"])

            XCTAssertEqual(direction.expectedSourceLanguage, "Japanese")
            XCTAssertEqual(direction.targetLanguage, "Simplified Chinese")
            XCTAssertTrue(TranslationDirection.prefersSimplifiedChineseInterface(for: [locale]))
            XCTAssertFalse(TranslationDirection.prefersTraditionalChineseInterface(for: [locale]))
        }
    }

    func testSourceLanguageCanBeSelectedRegardlessOfInterfaceLanguage() {
        let english = TranslationDirection.forPreferredLanguages(
            ["ja-JP"],
            sourceLanguage: .english
        )
        let simplifiedChinese = TranslationDirection.forPreferredLanguages(
            ["en-US"],
            sourceLanguage: .simplifiedChinese
        )
        let traditionalChinese = TranslationDirection.forPreferredLanguages(
            ["en-US"],
            sourceLanguage: .traditionalChinese
        )

        XCTAssertEqual(english.expectedSourceLanguage, "English")
        XCTAssertEqual(english.targetLanguage, "Japanese")
        XCTAssertEqual(simplifiedChinese.expectedSourceLanguage, "Simplified Chinese")
        XCTAssertEqual(simplifiedChinese.targetLanguage, "English")
        XCTAssertEqual(traditionalChinese.expectedSourceLanguage, "Traditional Chinese")
        XCTAssertEqual(traditionalChinese.targetLanguage, "English")
    }

    func testMatchingSourceAndInterfaceFallsBackToJapanese() {
        let direction = TranslationDirection.forPreferredLanguages(
            ["zh-Hans-CN"],
            sourceLanguage: .simplifiedChinese
        )

        XCTAssertEqual(direction.expectedSourceLanguage, "Simplified Chinese")
        XCTAssertEqual(direction.targetLanguage, "Japanese")
    }

    func testEditableSelectionReversesTheReadingDirection() {
        let direction = TranslationDirection.forEditableSelectionReplacement(
            preferredLanguages: ["en-US"],
            sourceLanguage: .japanese
        )

        XCTAssertEqual(direction.expectedSourceLanguage, "English")
        XCTAssertEqual(direction.targetLanguage, "Japanese")
    }

    func testInterfaceLanguageIsExcludedFromSourceOptions() {
        XCTAssertFalse(
            TranslationDirection.availableSourceLanguages(for: ["en-US"]).contains(.english)
        )
        XCTAssertFalse(
            TranslationDirection.availableSourceLanguages(for: ["ja-JP"]).contains(.japanese)
        )
        XCTAssertFalse(
            TranslationDirection.availableSourceLanguages(for: ["zh-Hans-CN"])
                .contains(.simplifiedChinese)
        )
        XCTAssertFalse(
            TranslationDirection.availableSourceLanguages(for: ["zh-Hant-TW"])
                .contains(.traditionalChinese)
        )
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
        XCTAssertTrue(instructions.contains("next-step instruction in Japanese"))
        XCTAssertFalse(instructions.contains("Always answer in English"))
    }

    func testTraditionalChineseInterfaceRequestsTraditionalChineseScreenshotAnswers() {
        let instructions = TranslationDirection.screenshotLanguageBehaviorInstructions(
            for: ["zh-Hant-TW", "en-US"]
        )

        XCTAssertTrue(instructions.contains("Always answer in Traditional Chinese"))
        XCTAssertTrue(instructions.contains("next-step instruction in Traditional Chinese"))
    }

    func testSimplifiedChineseInterfaceRequestsSimplifiedChineseScreenshotAnswers() {
        let instructions = TranslationDirection.screenshotLanguageBehaviorInstructions(
            for: ["zh-Hans-CN", "en-US"]
        )

        XCTAssertTrue(instructions.contains("Always answer in Simplified Chinese"))
        XCTAssertTrue(instructions.contains("next-step instruction in Simplified Chinese"))
    }

    func testScreenshotInstructionsIncludeSelectedSourceLanguage() {
        let instructions = TranslationDirection.screenshotLanguageBehaviorInstructions(
            for: ["en-US"],
            sourceLanguage: .traditionalChinese
        )

        XCTAssertTrue(instructions.contains("expect the source language to be Traditional Chinese"))
    }
}
