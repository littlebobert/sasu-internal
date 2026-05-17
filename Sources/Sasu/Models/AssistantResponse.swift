import AppKit
import Foundation

struct AssistantResponse: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let createdAt = Date()
    let prompt: String
    let actionSuggestion: HighlightSuggestion?
}

struct ChatTranscriptMessage: Identifiable, Equatable {
    enum Role: String {
        case screenshot = "Screenshot"
        case user = "You"
        case assistant = "Sasu"
        case error = "Error"
    }

    let id = UUID()
    let role: Role
    let text: String
    let imageData: Data?
    let actionSuggestion: HighlightSuggestion?
    let createdAt = Date()

    init(
        role: Role,
        text: String,
        imageData: Data? = nil,
        actionSuggestion: HighlightSuggestion? = nil
    ) {
        self.role = role
        self.text = text
        self.imageData = imageData
        self.actionSuggestion = actionSuggestion
    }

    static func == (lhs: ChatTranscriptMessage, rhs: ChatTranscriptMessage) -> Bool {
        lhs.id == rhs.id
    }

    var image: NSImage? {
        imageData.flatMap(NSImage.init(data:))
    }
}
