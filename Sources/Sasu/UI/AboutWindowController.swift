import AppKit
import SwiftUI

@MainActor
final class AboutWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onClose: (() -> Void)?

    func show(onClose: @escaping () -> Void) {
        self.onClose = onClose

        if window == nil {
            window = makeWindow()
        }

        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 215),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "About Sasu"
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: AboutView())

        return window
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

private struct AboutView: View {
    @State private var reportError: String?

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.3"
    }

    private var appIcon: NSImage {
        NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 60, height: 60)

            VStack(spacing: 4) {
                Text("Sasu")
                    .font(.title2.bold())
                Text("Version \(version)")
                    .foregroundStyle(.secondary)
            }

            Text("On-screen guidance for macOS")
                .multilineTextAlignment(.center)

            Link("Made in Japan", destination: URL(string: "https://sasu.jp")!)
                .font(.callout)

            Button("Report a Bug") {
                reportBug()
            }
            .buttonStyle(.bordered)
            .padding(.top, 5)

            if let reportError {
                Text(reportError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .frame(width: 280, height: 215)
    }

    private func reportBug() {
        do {
            DiagnosticLogger.log("User opened bug report email from About window.", category: "BugReport")
            let reportURL = try DiagnosticLogger.makeBugReport()
            let reportText = DiagnosticLogger.makeBugReportText()
            guard let service = NSSharingService(named: .composeEmail) else {
                revealReport(reportURL)
                reportError = "Could not open Mail. The report file was shown in Finder."
                return
            }

            service.recipients = ["justin.garcia@gmail.com"]
            service.subject = "Sasu Bug Report"
            service.perform(withItems: [
                """
                Hi Justin,

                I ran into a Sasu issue. The diagnostic report is included below.

                What happened:

                ---

                \(reportText)
                """,
            ])
            reportError = nil
        } catch {
            reportError = "Could not create report: \(error.localizedDescription)"
        }
    }

    private func revealReport(_ reportURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([reportURL])
    }
}
