import AppKit
import SwiftUI

@MainActor
final class AnswerWindowController {
    private var window: NSPanel?

    func show(appModel: AppModel, activate: Bool = true) {
        if window == nil {
            window = makeWindow(appModel: appModel)
        }

        window?.level = .floating
        guard activate else { return }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow(appModel: AppModel) -> NSPanel {
        let panel = NSPanel(
            contentRect: initialFrame(),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = "Sasu"
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.isReleasedWhenClosed = false
        panel.setFrameAutosaveName("SasuAnswerWindow")
        panel.contentView = NSHostingView(
            rootView: AnswerPanelView()
                .environmentObject(appModel)
        )

        return panel
    }

    private func initialFrame() -> NSRect {
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(max(screenFrame.width * 0.32, 460), 560)
        let height = min(max(screenFrame.height * 0.65, 520), 760)
        let x = screenFrame.maxX - width - 24
        let y = screenFrame.midY - height / 2

        return NSRect(x: x, y: y, width: width, height: height)
    }
}
