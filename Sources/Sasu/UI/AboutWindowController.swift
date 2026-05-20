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
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 230),
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

            Text("On-screen guidance for macOS.")
                .multilineTextAlignment(.center)

            Text("Made in Japan.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Link("More Info", destination: URL(string: "http://sasu.jp/")!)
        }
        .padding(12)
        .frame(width: 300, height: 230)
    }
}
