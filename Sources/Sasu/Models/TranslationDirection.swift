import Foundation

struct TranslationDirection {
    let targetLanguage: String
    let expectedSourceLanguage: String
    let alreadyInTargetInstruction: String

    static var prefersJapaneseInterface: Bool {
        Locale.preferredLanguages.first?.hasPrefix("ja") == true
    }

    static var forUserInterface: TranslationDirection {
        if prefersJapaneseInterface {
            return TranslationDirection(
                targetLanguage: "English",
                expectedSourceLanguage: "Japanese",
                alreadyInTargetInstruction: "If the source text is in English instead of Japanese, translate it into Japanese."
            )
        }

        return TranslationDirection(
            targetLanguage: "Japanese",
            expectedSourceLanguage: "English",
            alreadyInTargetInstruction: "If the source text is in Japanese instead of English, translate it into English."
        )
    }

    static var screenshotLanguageBehaviorInstructions: String {
        if prefersJapaneseInterface {
            return """
            Language behavior:
            - Always answer in English, even if the user's request is in Japanese.
            - Preserve visible UI labels in their original on-screen language. Quote the Japanese label first, then add a short translation in parentheses, such as `予定` ("Schedule").
            - For actionSuggestion.label, use a short user-facing target label in English. Include the original on-screen label in actionSuggestion.reason or answer when it is in another language.
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
