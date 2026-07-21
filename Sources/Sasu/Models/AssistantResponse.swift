import AppKit
import Foundation

struct AssistantResponse: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let createdAt = Date()
    let prompt: String
    let actionSuggestion: HighlightSuggestion?
}

struct RubyTextSegment: Codable, Equatable {
    let text: String
    let reading: String?
}

struct ChatTranscriptMessage: Identifiable, Equatable {
    enum SourceKind {
        case clipboard
        case selection

        var displayLabel: String {
            switch self {
            case .clipboard:
                return String(localized: "Clipboard text:")
            case .selection:
                return String(localized: "Selected text:")
            }
        }
    }

    enum Role: String {
        case screenshot = "Screenshot"
        case user = "You"
        case assistant = "Sasu"
        case error = "Error"

        var displayLabel: String {
            switch self {
            case .screenshot:
                return String(localized: "Screenshot")
            case .user:
                return String(localized: "You")
            case .assistant:
                return String(localized: "Sasu")
            case .error:
                return String(localized: "Error")
            }
        }
    }

    let id: UUID
    let role: Role
    let text: String
    let imageData: Data?
    let browserPageContext: BrowserPageContext?
    let browserPageCaptureIssue: String?
    let sourceReadings: [RubyTextSegment]?
    let sourceKind: SourceKind?
    let actionSuggestion: HighlightSuggestion?
    let createdAt = Date()

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        imageData: Data? = nil,
        browserPageContext: BrowserPageContext? = nil,
        browserPageCaptureIssue: String? = nil,
        sourceReadings: [RubyTextSegment]? = nil,
        sourceKind: SourceKind? = nil,
        actionSuggestion: HighlightSuggestion? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.imageData = imageData
        self.browserPageContext = browserPageContext
        self.browserPageCaptureIssue = browserPageCaptureIssue
        self.sourceReadings = sourceReadings
        self.sourceKind = sourceKind
        self.actionSuggestion = actionSuggestion
    }

    static func == (lhs: ChatTranscriptMessage, rhs: ChatTranscriptMessage) -> Bool {
        lhs.id == rhs.id
    }

    var image: NSImage? {
        imageData.flatMap(NSImage.init(data:))
    }

    var machineContextText: String {
        switch sourceKind {
        case .clipboard:
            return "Clipboard text: \(text)"
        case .selection:
            return "Selected text: \(text)"
        case nil:
            return text
        }
    }

    var localizedTranscriptText: String {
        guard let sourceKind else { return text }
        return "\(sourceKind.displayLabel) \(text)"
    }
}
