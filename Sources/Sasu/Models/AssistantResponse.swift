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
    let browserPageContext: BrowserPageContext?
    let browserPageCaptureIssue: String?
    let actionSuggestion: HighlightSuggestion?
    let createdAt = Date()

    init(
        role: Role,
        text: String,
        imageData: Data? = nil,
        browserPageContext: BrowserPageContext? = nil,
        browserPageCaptureIssue: String? = nil,
        actionSuggestion: HighlightSuggestion? = nil
    ) {
        self.role = role
        self.text = text
        self.imageData = imageData
        self.browserPageContext = browserPageContext
        self.browserPageCaptureIssue = browserPageCaptureIssue
        self.actionSuggestion = actionSuggestion
    }

    static func == (lhs: ChatTranscriptMessage, rhs: ChatTranscriptMessage) -> Bool {
        lhs.id == rhs.id
    }

    var image: NSImage? {
        imageData.flatMap(NSImage.init(data:))
    }
}
