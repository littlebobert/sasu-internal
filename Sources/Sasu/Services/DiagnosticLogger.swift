import AppKit
import Foundation

enum DiagnosticLogger {
    private static let queue = DispatchQueue(label: "dev.sasu.Sasu.DiagnosticLogger")
    private static let maxLogBytes = 512_000
    private static let maxBugReportLogLines = 220

    private static var logsDirectory: URL {
        get throws {
            let baseURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = baseURL.appendingPathComponent("Sasu/Logs", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    static var logFileURL: URL {
        get throws {
            try logsDirectory.appendingPathComponent("sasu.log", isDirectory: false)
        }
    }

    static func log(_ message: String, category: String = "App") {
        let line = "\(Self.timestamp()) [\(category)] \(message)\n"
        queue.async {
            do {
                let fileURL = try logFileURL
                rotateLogIfNeeded(fileURL: fileURL)

                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let handle = try FileHandle(forWritingTo: fileURL)
                    try handle.seekToEnd()
                    if let data = line.data(using: .utf8) {
                        try handle.write(contentsOf: data)
                    }
                    try handle.close()
                } else {
                    try line.write(to: fileURL, atomically: true, encoding: .utf8)
                }
            } catch {
                // Diagnostics must never interfere with the app.
            }
        }
    }

    static func makeBugReport() throws -> URL {
        try queue.sync {
            let directory = try logsDirectory
            let reportURL = directory.appendingPathComponent("Sasu-Bug-Report.txt", isDirectory: false)
            let report = makeBugReportText()
            try report.write(to: reportURL, atomically: true, encoding: .utf8)
            return reportURL
        }
    }

    static func makeBugReportText() -> String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let backendURL = bundle.object(forInfoDictionaryKey: "SASUBackendBaseURL") as? String ?? "unknown"
        let appcastURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "unknown"
        let bundleID = bundle.bundleIdentifier ?? "unknown"
        let fullLogText = (try? String(contentsOf: logFileURL, encoding: .utf8)) ?? "No diagnostic log found."
        let logText = recentLogText(from: fullLogText)

        return """
        Sasu Bug Report
        ===============

        App version: \(version) (\(build))
        Bundle ID: \(bundleID)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Architecture: \(ProcessInfo.processInfo.machineHardwareName)
        App path: \(bundle.bundlePath)
        Backend URL: \(backendURL)
        Sparkle appcast URL: \(appcastURL)
        Screen Recording permission: \(CGPreflightScreenCaptureAccess() ? "granted" : "not granted")

        Recent diagnostic log
        =====================

        \(logText)
        """
    }

    private static func rotateLogIfNeeded(fileURL: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > maxLogBytes else {
            return
        }

        let rotatedURL = fileURL.deletingLastPathComponent().appendingPathComponent("sasu.previous.log")
        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: fileURL, to: rotatedURL)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func recentLogText(from fullLogText: String) -> String {
        let lines = fullLogText.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maxBugReportLogLines else { return fullLogText }

        return lines
            .suffix(maxBugReportLogLines)
            .joined(separator: "\n")
    }
}

private extension ProcessInfo {
    var machineHardwareName: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}
