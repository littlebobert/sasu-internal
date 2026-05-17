import CoreGraphics
import Foundation

struct AssistantResult: Equatable {
    let answer: String
    let actionSuggestion: HighlightSuggestion?
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
