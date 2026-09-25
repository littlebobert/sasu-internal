import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation

struct SelectionAutomationService {
    private let clipboardCopyDelayNanoseconds: UInt64 = 120_000_000
    private let clipboardPasteDelayNanoseconds: UInt64 = 80_000_000

    func hasAccessibilityAccess() -> Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func copySelectedText(from pasteboard: NSPasteboard = .general) async throws -> (text: String, backup: PasteboardBackup) {
        guard hasAccessibilityAccess() else {
            throw SelectionAutomationError.accessibilityRequired
        }
        try requirePostEventAccess()

        let backup = PasteboardBackup.capture(from: pasteboard)
        let sentinel = "dev.sasu.Sasu.selection-sentinel.\(UUID().uuidString)"
        pasteboard.clearContents()
        pasteboard.setString(sentinel, forType: .string)

        do {
            try postCommandKey(keyCode: CGKeyCode(kVK_ANSI_C))

            try await Task.sleep(nanoseconds: clipboardCopyDelayNanoseconds)

            guard let copiedText = pasteboard.string(forType: .string),
                  copiedText != sentinel else {
                let frontmostBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
                DiagnosticLogger.log(
                    "Copy command produced no text. frontmostBundle=\(frontmostBundle) pasteboardChanged=\(pasteboard.string(forType: .string) != sentinel) axTrusted=\(AXIsProcessTrusted()) postEventAccess=\(CGPreflightPostEventAccess())",
                    category: "Selection"
                )
                throw SelectionAutomationError.noSelection
            }

            let trimmedText = copiedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                throw SelectionAutomationError.emptySelection
            }

            return (copiedText, backup)
        } catch {
            backup.restore(to: pasteboard)
            throw error
        }
    }

    func pasteTranslation(
        _ text: String,
        restoring backup: PasteboardBackup,
        to pasteboard: NSPasteboard = .general
    ) async throws {
        guard hasAccessibilityAccess() else {
            throw SelectionAutomationError.accessibilityRequired
        }
        try requirePostEventAccess()

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try postCommandKey(keyCode: CGKeyCode(kVK_ANSI_V))

        try await Task.sleep(nanoseconds: clipboardPasteDelayNanoseconds)

        backup.restore(to: pasteboard)
    }

    // AXIsProcessTrusted() can stay true while macOS silently drops synthetic
    // key events (e.g. a stale grant after a reboot), so check posting separately.
    private func requirePostEventAccess() throws {
        guard CGPreflightPostEventAccess() else {
            DiagnosticLogger.log("Post-event access is missing even though Accessibility is trusted.", category: "Selection")
            CGRequestPostEventAccess()
            throw SelectionAutomationError.accessibilityRequired
        }
    }

    private func postCommandKey(keyCode: CGKeyCode) throws {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw SelectionAutomationError.eventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }

}

enum SelectionAutomationError: LocalizedError {
    case accessibilityRequired
    case noSelection
    case emptySelection
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired:
            return String(localized: "Enable Sasu in System Settings > Privacy & Security > Accessibility to translate selected text in other apps.")
        case .noSelection:
            return String(localized: "No text was selected. Select text in the app you are editing, then choose Translate & Replace again.")
        case .emptySelection:
            return String(localized: "The selected text is empty. Select text to translate, then choose Translate & Replace again.")
        case .eventCreationFailed:
            return String(localized: "Sasu could not send the copy or paste command.")
        }
    }
}
