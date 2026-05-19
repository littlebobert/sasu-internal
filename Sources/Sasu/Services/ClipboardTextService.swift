import AppKit
import Foundation

struct ClipboardTextService {
    func readText() throws -> String {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            throw ClipboardTextError.noText
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ClipboardTextError.emptyText
        }

        return trimmedText
    }
}

enum ClipboardTextError: LocalizedError {
    case noText
    case emptyText

    var errorDescription: String? {
        switch self {
        case .noText:
            return "The clipboard does not contain text. Copy text first, then press Translate Clipboard."
        case .emptyText:
            return "The clipboard text is empty. Copy the text you want translated, then press Translate Clipboard."
        }
    }
}
