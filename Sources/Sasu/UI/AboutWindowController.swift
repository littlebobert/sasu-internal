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
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 290),
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
        VStack(spacing: 6) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 64, height: 64)

            VStack(spacing: 4) {
                Text("Sasu")
                    .font(.title2.bold())
                Text("Version \(version)")
                    .foregroundStyle(.secondary)
            }

            Text("On-screen guidance for macOS")
                .multilineTextAlignment(.center)

            Link("Made in Japan", destination: URL(string: "http://sasu.jp")!)
                .font(.callout)

            Button("Report a Bug") {
                reportBug()
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)

            if let reportError {
                Text(reportError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .frame(width: 320, height: 290)
    }

    private func reportBug() {
        do {
            DiagnosticLogger.log("User opened bug report email from About window.", category: "BugReport")
            let reportURL = try DiagnosticLogger.makeBugReport()
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

                I ran into a Sasu issue. I attached the diagnostic report.

                What happened:

                """,
                reportURL
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
