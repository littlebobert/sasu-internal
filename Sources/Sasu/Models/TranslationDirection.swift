import Foundation

struct TranslationDirection {
    let targetLanguage: String
    let expectedSourceLanguage: String

    static var prefersJapaneseInterface: Bool {
        prefersJapaneseInterface(for: Locale.preferredLanguages)
    }

    static func prefersJapaneseInterface(for preferredLanguages: [String]) -> Bool {
        preferredLanguages.first?.hasPrefix("ja") == true
    }

    static var forUserInterface: TranslationDirection {
        forPreferredLanguages(Locale.preferredLanguages)
    }

    static func forPreferredLanguages(_ preferredLanguages: [String]) -> TranslationDirection {
        if prefersJapaneseInterface(for: preferredLanguages) {
            return TranslationDirection(
                targetLanguage: "Japanese",
                expectedSourceLanguage: "English"
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

        return """
        Language behavior:
        - Answer in the same language as the user's request unless the user asks otherwise.
        - Preserve visible UI labels in their original on-screen language. For Japanese UI, quote the Japanese label first, then add a short translation in parentheses, such as `予定` ("Schedule").
        - For actionSuggestion.label, use a short user-facing target label in the same language as the user's request. If the visible UI label is in another language, include that original on-screen label in actionSuggestion.reason or answer.
        """
    }
}
