import Foundation

enum TranslationSourceLanguage: String, CaseIterable, Identifiable {
    case japanese
    case english
    case simplifiedChinese
    case traditionalChinese

    var id: String { rawValue }

    var label: String {
        switch self {
        case .japanese:
            return "Japanese"
        case .english:
            return "English"
        case .simplifiedChinese:
            return "Simplified Chinese"
        case .traditionalChinese:
            return "Traditional Chinese"
        }
    }

    var languageName: String { label }
}

struct TranslationDirection {
    let targetLanguage: String
    let expectedSourceLanguage: String

    static var prefersJapaneseInterface: Bool {
        prefersJapaneseInterface(for: Locale.preferredLanguages)
    }

    static func prefersJapaneseInterface(for preferredLanguages: [String]) -> Bool {
        normalizedPrimaryLanguage(from: preferredLanguages)?.hasPrefix("ja") == true
    }

    static var prefersTraditionalChineseInterface: Bool {
        prefersTraditionalChineseInterface(for: Locale.preferredLanguages)
    }

    static func prefersTraditionalChineseInterface(for preferredLanguages: [String]) -> Bool {
        guard let language = normalizedPrimaryLanguage(from: preferredLanguages) else {
            return false
        }

        return language.hasPrefix("zh-hant")
            || language == "zh-tw"
            || language.hasPrefix("zh-tw-")
            || language == "zh-hk"
            || language.hasPrefix("zh-hk-")
            || language == "zh-mo"
            || language.hasPrefix("zh-mo-")
    }

    static var prefersSimplifiedChineseInterface: Bool {
        prefersSimplifiedChineseInterface(for: Locale.preferredLanguages)
    }

    static func prefersSimplifiedChineseInterface(for preferredLanguages: [String]) -> Bool {
        guard let language = normalizedPrimaryLanguage(from: preferredLanguages) else {
            return false
        }

        return language.hasPrefix("zh-hans")
            || language == "zh-cn"
            || language.hasPrefix("zh-cn-")
            || language == "zh-sg"
            || language.hasPrefix("zh-sg-")
    }

    static var forUserInterface: TranslationDirection {
        forPreferredLanguages(Locale.preferredLanguages, sourceLanguage: .japanese)
    }

    static var availableSourceLanguagesForUserInterface: [TranslationSourceLanguage] {
        availableSourceLanguages(for: Locale.preferredLanguages)
    }

    static func availableSourceLanguages(
        for preferredLanguages: [String]
    ) -> [TranslationSourceLanguage] {
        let interfaceLanguage = interfaceLanguage(for: preferredLanguages)
        return TranslationSourceLanguage.allCases.filter { $0 != interfaceLanguage }
    }

    static func forUserInterface(sourceLanguage: TranslationSourceLanguage) -> TranslationDirection {
        forPreferredLanguages(Locale.preferredLanguages, sourceLanguage: sourceLanguage)
    }

    static func forEditableSelectionReplacement(
        sourceLanguage: TranslationSourceLanguage
    ) -> TranslationDirection {
        forEditableSelectionReplacement(
            preferredLanguages: Locale.preferredLanguages,
            sourceLanguage: sourceLanguage
        )
    }

    static func forEditableSelectionReplacement(
        preferredLanguages: [String],
        sourceLanguage: TranslationSourceLanguage
    ) -> TranslationDirection {
        let readingDirection = forPreferredLanguages(
            preferredLanguages,
            sourceLanguage: sourceLanguage
        )
        return TranslationDirection(
            targetLanguage: sourceLanguage.languageName,
            expectedSourceLanguage: readingDirection.targetLanguage
        )
    }

    static func forPreferredLanguages(
        _ preferredLanguages: [String],
        sourceLanguage: TranslationSourceLanguage = .japanese
    ) -> TranslationDirection {
        let preferredTargetLanguage = interfaceLanguage(for: preferredLanguages).languageName

        let targetLanguage = preferredTargetLanguage == sourceLanguage.languageName
            ? (sourceLanguage == .japanese ? "English" : "Japanese")
            : preferredTargetLanguage

        return TranslationDirection(
            targetLanguage: targetLanguage,
            expectedSourceLanguage: sourceLanguage.languageName
        )
    }

    private static func interfaceLanguage(
        for preferredLanguages: [String]
    ) -> TranslationSourceLanguage {
        if prefersJapaneseInterface(for: preferredLanguages) {
            return .japanese
        } else if prefersTraditionalChineseInterface(for: preferredLanguages) {
            return .traditionalChinese
        } else if prefersSimplifiedChineseInterface(for: preferredLanguages) {
            return .simplifiedChinese
        } else {
            return .english
        }
    }

    static var screenshotLanguageBehaviorInstructions: String {
        screenshotLanguageBehaviorInstructions(for: Locale.preferredLanguages)
    }

    static func screenshotLanguageBehaviorInstructions(
        for preferredLanguages: [String],
        sourceLanguage: TranslationSourceLanguage = .japanese
    ) -> String {
        let languageInstructions: String
        if prefersJapaneseInterface(for: preferredLanguages) {
            languageInstructions = """
            Language behavior:
            - Always answer in Japanese, even if the user's request is in English.
            - Preserve visible UI labels in their original on-screen language. Quote an English label first, then add a short Japanese translation in parentheses, such as `Schedule`（「予定」）.
            - For actionSuggestion.label, use a concise, complete next-step instruction in Japanese. Include the original on-screen label in actionSuggestion.reason or answer when it is in another language.
            """
        } else if prefersTraditionalChineseInterface(for: preferredLanguages) {
            languageInstructions = traditionalChineseScreenshotInstructions
        } else if prefersSimplifiedChineseInterface(for: preferredLanguages) {
            languageInstructions = simplifiedChineseScreenshotInstructions
        } else {
            languageInstructions = """
            Language behavior:
            - Answer in the same language as the user's request unless the user asks otherwise.
            - Preserve visible UI labels in their original on-screen language. For Japanese UI, quote the Japanese label first, then add a short translation in parentheses, such as `予定` ("Schedule").
            - For actionSuggestion.label, use a concise, complete next-step instruction in the same language as the user's request. If the visible UI label is in another language, include that original on-screen label in actionSuggestion.reason or answer.
            """
        }

        return languageInstructions + """

        - When the user asks for a translation, expect the source language to be \(sourceLanguage.languageName) unless they explicitly say otherwise.
        """
    }

    private static var traditionalChineseScreenshotInstructions: String {
        """
        Language behavior:
        - Always answer in Traditional Chinese, even if the user's request is in English or Japanese.
        - Preserve visible UI labels in their original on-screen language, then add a short Traditional Chinese translation in parentheses.
        - For actionSuggestion.label, use a concise, complete next-step instruction in Traditional Chinese. Include the original on-screen label in actionSuggestion.reason or answer when it is in another language.
        """
    }

    private static var simplifiedChineseScreenshotInstructions: String {
        """
        Language behavior:
        - Always answer in Simplified Chinese, even if the user's request is in English or Japanese.
        - Preserve visible UI labels in their original on-screen language, then add a short Simplified Chinese translation in parentheses.
        - For actionSuggestion.label, use a concise, complete next-step instruction in Simplified Chinese. Include the original on-screen label in actionSuggestion.reason or answer when it is in another language.
        """
    }

    private static func normalizedPrimaryLanguage(from preferredLanguages: [String]) -> String? {
        preferredLanguages.first?
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }
}
