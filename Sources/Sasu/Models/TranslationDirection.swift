import Foundation

enum TranslationLanguagePair: String, CaseIterable, Identifiable {
    case automatic
    case traditionalChineseJapanese
    case traditionalChineseEnglish
    case simplifiedChineseJapanese
    case simplifiedChineseEnglish

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .traditionalChineseJapanese:
            return "Traditional Chinese ↔ Japanese"
        case .traditionalChineseEnglish:
            return "Traditional Chinese ↔ English"
        case .simplifiedChineseJapanese:
            return "Simplified Chinese ↔ Japanese"
        case .simplifiedChineseEnglish:
            return "Simplified Chinese ↔ English"
        }
    }
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
        forPreferredLanguages(Locale.preferredLanguages)
    }

    static func forUserInterface(languagePair: TranslationLanguagePair) -> TranslationDirection {
        forPreferredLanguages(Locale.preferredLanguages, languagePair: languagePair)
    }

    static func forPreferredLanguages(
        _ preferredLanguages: [String],
        languagePair: TranslationLanguagePair = .automatic
    ) -> TranslationDirection {
        switch languagePair {
        case .traditionalChineseJapanese:
            return TranslationDirection(
                targetLanguage: "Traditional Chinese",
                expectedSourceLanguage: "Japanese"
            )
        case .traditionalChineseEnglish:
            return TranslationDirection(
                targetLanguage: "Traditional Chinese",
                expectedSourceLanguage: "English"
            )
        case .simplifiedChineseJapanese:
            return TranslationDirection(
                targetLanguage: "Simplified Chinese",
                expectedSourceLanguage: "Japanese"
            )
        case .simplifiedChineseEnglish:
            return TranslationDirection(
                targetLanguage: "Simplified Chinese",
                expectedSourceLanguage: "English"
            )
        case .automatic:
            break
        }

        if prefersJapaneseInterface(for: preferredLanguages) {
            return TranslationDirection(
                targetLanguage: "Japanese",
                expectedSourceLanguage: "English"
            )
        }

        if prefersTraditionalChineseInterface(for: preferredLanguages) {
            return TranslationDirection(
                targetLanguage: "Traditional Chinese",
                expectedSourceLanguage: "Japanese"
            )
        }

        if prefersSimplifiedChineseInterface(for: preferredLanguages) {
            return TranslationDirection(
                targetLanguage: "Simplified Chinese",
                expectedSourceLanguage: "Japanese"
            )
        }

        return TranslationDirection(
            targetLanguage: "English",
            expectedSourceLanguage: "Japanese"
        )
    }

    static var screenshotLanguageBehaviorInstructions: String {
        screenshotLanguageBehaviorInstructions(for: Locale.preferredLanguages)
    }

    static func screenshotLanguageBehaviorInstructions(for preferredLanguages: [String]) -> String {
        if prefersJapaneseInterface(for: preferredLanguages) {
            return """
            Language behavior:
            - Always answer in Japanese, even if the user's request is in English.
            - Preserve visible UI labels in their original on-screen language. Quote an English label first, then add a short Japanese translation in parentheses, such as `Schedule`（「予定」）.
            - For actionSuggestion.label, use a short user-facing target label in Japanese. Include the original on-screen label in actionSuggestion.reason or answer when it is in another language.
            """
        }

        if prefersTraditionalChineseInterface(for: preferredLanguages) {
            return """
            Language behavior:
            - Always answer in Traditional Chinese, even if the user's request is in English or Japanese.
            - Preserve visible UI labels in their original on-screen language, then add a short Traditional Chinese translation in parentheses.
            - For actionSuggestion.label, use a short user-facing target label in Traditional Chinese. Include the original on-screen label in actionSuggestion.reason or answer when it is in another language.
            """
        }

        if prefersSimplifiedChineseInterface(for: preferredLanguages) {
            return """
            Language behavior:
            - Always answer in Simplified Chinese, even if the user's request is in English or Japanese.
            - Preserve visible UI labels in their original on-screen language, then add a short Simplified Chinese translation in parentheses.
            - For actionSuggestion.label, use a short user-facing target label in Simplified Chinese. Include the original on-screen label in actionSuggestion.reason or answer when it is in another language.
            """
        }

        return """
        Language behavior:
        - Answer in the same language as the user's request unless the user asks otherwise.
        - Preserve visible UI labels in their original on-screen language. For Japanese UI, quote the Japanese label first, then add a short translation in parentheses, such as `予定` ("Schedule").
        - For actionSuggestion.label, use a short user-facing target label in the same language as the user's request. If the visible UI label is in another language, include that original on-screen label in actionSuggestion.reason or answer.
        """
    }

    private static func normalizedPrimaryLanguage(from preferredLanguages: [String]) -> String? {
        preferredLanguages.first?
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }
}
