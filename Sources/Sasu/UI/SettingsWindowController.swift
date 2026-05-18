import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onClose: (() -> Void)?

    func show(appModel: AppModel, onClose: @escaping () -> Void) {
        self.onClose = onClose

        if window == nil {
            window = makeWindow(appModel: appModel)
        }

        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    private func makeWindow(appModel: AppModel) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Sasu Settings"
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: SettingsView()
                .environmentObject(appModel)
                .frame(width: 520, height: 620)
        )

        return window
    }
}
