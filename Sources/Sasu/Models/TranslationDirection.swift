import Foundation

struct TranslationDirection {
    let targetLanguage: String
    let expectedSourceLanguage: String
    let alreadyInTargetInstruction: String

    static var forUserInterface: TranslationDirection {
        if Locale.preferredLanguages.first?.hasPrefix("ja") == true {
            return TranslationDirection(
                targetLanguage: "English",
                expectedSourceLanguage: "Japanese",
                alreadyInTargetInstruction: "If the source text is already natural English, return it unchanged."
            )
        }

        return TranslationDirection(
            targetLanguage: "Japanese",
            expectedSourceLanguage: "English",
            alreadyInTargetInstruction: "If the source text is already natural Japanese, return it unchanged."
        )
    }
}
