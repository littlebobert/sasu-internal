import Foundation

struct SafariPageCaptureService {
    static let safariBundleIdentifier = "com.apple.Safari"

    private let maxTextCharacters = 80_000

    func captureCurrentPage() throws -> BrowserPageContext {
        guard let script = NSAppleScript(source: Self.scriptSource) else {
            throw SafariPageCaptureError.scriptFailed("Sasu could not prepare the Safari capture script.")
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw Self.captureError(from: errorInfo)
        }

        guard let title = descriptor.atIndex(1)?.stringValue,
              let url = descriptor.atIndex(2)?.stringValue,
              let rawText = descriptor.atIndex(3)?.stringValue else {
            throw SafariPageCaptureError.unexpectedResult
        }

        let normalizedText = Self.normalizedPageText(rawText)
        let truncatedText: String
        let isTruncated: Bool
        if normalizedText.count > maxTextCharacters {
            let endIndex = normalizedText.index(normalizedText.startIndex, offsetBy: maxTextCharacters)
            truncatedText = String(normalizedText[..<endIndex])
            isTruncated = true
        } else {
            truncatedText = normalizedText
            isTruncated = false
        }

        guard !truncatedText.isEmpty else {
            throw SafariPageCaptureError.emptyPageText
        }

        return BrowserPageContext(
            browserName: "Safari",
            pageTitle: title.trimmingCharacters(in: .whitespacesAndNewlines),
            pageURL: url.trimmingCharacters(in: .whitespacesAndNewlines),
            text: truncatedText,
            originalCharacterCount: normalizedText.count,
            isTruncated: isTruncated
        )
    }

    private static var scriptSource: String {
        let javaScript = #"(() => { const text = document.body ? document.body.innerText : ""; return text; })();"#

        return """
        tell application id "\(safariBundleIdentifier)"
            if not (exists front window) then error "Safari has no open window."
            set pageTitle to name of current tab of front window
            set pageURL to URL of current tab of front window
            set pageText to do JavaScript \(appleScriptStringLiteral(javaScript)) in current tab of front window
            return {pageTitle, pageURL, pageText}
        end tell
        """
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func normalizedPageText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func captureError(from errorInfo: NSDictionary) -> SafariPageCaptureError {
        let number = (errorInfo["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue
        let message = (errorInfo["NSAppleScriptErrorMessage"] as? String)
            ?? (errorInfo["NSAppleScriptErrorBriefMessage"] as? String)
            ?? "Safari page capture failed."

        if number == -1743 || message.localizedCaseInsensitiveContains("not authorized") {
            return .automationPermissionDenied
        }

        if message.localizedCaseInsensitiveContains("allow javascript")
            || message.localizedCaseInsensitiveContains("javascript from apple events")
            || message.localizedCaseInsensitiveContains("not allowed to execute javascript") {
            return .javaScriptPermissionRequired
        }

        if message.localizedCaseInsensitiveContains("no open window") {
            return .noOpenWindow
        }

        return .scriptFailed(message)
    }
}

enum SafariPageCaptureError: LocalizedError, Equatable {
    case automationPermissionDenied
    case javaScriptPermissionRequired
    case noOpenWindow
    case emptyPageText
    case unexpectedResult
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .automationPermissionDenied:
            return "Safari page content was not included because macOS Automation permission was denied. Enable Sasu under System Settings > Privacy & Security > Automation, then try again."
        case .javaScriptPermissionRequired:
            return "Safari blocked page text extraction. In Safari, enable Safari > Develop > Developer Settings > Allow JavaScript from Apple Events, then capture again."
        case .noOpenWindow:
            return "Safari page content was not included because Safari has no open window."
        case .emptyPageText:
            return "Safari page content was not included because the active tab did not expose readable text."
        case .unexpectedResult:
            return "Safari returned an unexpected response while Sasu was reading the page."
        case .scriptFailed(let message):
            return "Safari page content was not included: \(message)"
        }
    }
}
