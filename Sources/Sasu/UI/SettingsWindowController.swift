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

    func hide() {
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    private func makeWindow(appModel: AppModel) -> NSWindow {
        let contentSize = initialContentSize()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
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
                .frame(width: contentSize.width, height: contentSize.height)
        )

        return window
    }

    private func initialContentSize() -> NSSize {
        let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(560, max(480, visibleFrame.width - 80))
        let height = min(780, max(520, visibleFrame.height - 80))

        return NSSize(width: width, height: height)
    }
}
