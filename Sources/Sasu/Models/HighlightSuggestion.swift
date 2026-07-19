import CoreGraphics
import Foundation

struct AssistantResult: Equatable {
    let answer: String
    let actionSuggestion: HighlightSuggestion?
    let sourceText: String?

    init(
        answer: String,
        actionSuggestion: HighlightSuggestion?,
        sourceText: String? = nil
    ) {
        self.answer = answer
        self.actionSuggestion = actionSuggestion
        self.sourceText = sourceText
    }
}

struct HighlightSuggestion: Codable, Equatable {
    let label: String
    let exactText: String?
    let shape: HighlightShape
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let reason: String?

    func replacingRect(_ rect: CGRect) -> HighlightSuggestion {
        HighlightSuggestion(
            label: label,
            exactText: exactText,
            shape: shape,
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width,
            height: rect.height,
            reason: reason
        )
    }
}

enum HighlightShape: String, Codable {
    case rectangle
    case circle
}
