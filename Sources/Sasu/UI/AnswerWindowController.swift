import AppKit
import Combine
import SwiftUI

@MainActor
final class AnswerWindowController: NSObject, NSToolbarDelegate, NSToolbarItemValidation {
    private var window: NSPanel?
    private weak var appModel: AppModel?
    private var appModelObservation: AnyCancellable?
    private var isFloatingEnabled = true

    func show(appModel: AppModel, activate: Bool = true) {
        self.appModel = appModel
        observeAppModel(appModel)

        if window == nil {
            window = makeWindow(appModel: appModel)
        }

        window?.level = currentWindowLevel
        guard activate else { return }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setFloatingEnabled(_ isEnabled: Bool) {
        isFloatingEnabled = isEnabled
        window?.level = currentWindowLevel
    }

    func hide() {
        window?.orderOut(nil)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .captureScreen:
            return toolbarItem(
                identifier: itemIdentifier,
                label: "Capture",
                symbolNames: ["camera.viewfinder", "rectangle.dashed"],
                action: #selector(captureScreen)
            )
        case .translateClipboard:
            return toolbarItem(
                identifier: itemIdentifier,
                label: "Translate Clipboard",
                symbolNames: ["translate", "character.book.closed", "textformat"],
                action: #selector(translateClipboard)
            )
        case .copyAnswer:
            return toolbarItem(
                identifier: itemIdentifier,
                label: "Copy Answer",
                symbolNames: ["doc.on.doc", "doc.on.clipboard"],
                action: #selector(copyAnswer)
            )
        case .clearTranscript:
            return toolbarItem(
                identifier: itemIdentifier,
                label: "Clear",
                symbolNames: ["trash"],
                action: #selector(clearTranscript)
            )
        case .settings:
            return toolbarItem(
                identifier: itemIdentifier,
                label: "Settings",
                symbolNames: ["gearshape", "gear"],
                action: #selector(showSettings)
            )
        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            .captureScreen,
            .translateClipboard,
            .copyAnswer,
            .clearTranscript,
            .settings
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .captureScreen,
            .translateClipboard,
            .copyAnswer,
            .clearTranscript,
            .settings,
            .flexibleSpace,
            .space
        ]
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        guard let appModel else { return false }

        switch item.itemIdentifier {
        case .captureScreen, .translateClipboard:
            return !appModel.isRequestInFlight
        case .copyAnswer:
            return appModel.lastResponse != nil
        case .clearTranscript:
            return !appModel.transcriptMessages.isEmpty && !appModel.isRequestInFlight
        case .settings:
            return true
        default:
            return true
        }
    }

    private func makeWindow(appModel: AppModel) -> NSPanel {
        let panel = NSPanel(
            contentRect: initialFrame(),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = "Transcript"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.isExcludedFromWindowsMenu = false
        panel.isReleasedWhenClosed = false
        panel.setFrameAutosaveName("SasuAnswerWindow")
        panel.toolbar = makeToolbar()
        panel.toolbar?.displayMode = .labelOnly
        panel.toolbar?.sizeMode = .regular
        panel.toolbarStyle = .unified
        panel.contentView = NSHostingView(
            rootView: AnswerPanelView()
                .environmentObject(appModel)
        )

        return panel
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "SasuTranscriptToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .labelOnly
        toolbar.sizeMode = .regular
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        return toolbar
    }

    private func toolbarItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        symbolNames: [String],
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = Self.symbolImage(named: symbolNames)
        item.target = self
        item.action = action
        return item
    }

    private static func symbolImage(named symbolNames: [String]) -> NSImage? {
        for symbolName in symbolNames {
            if let image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: nil
            ) {
                return image
            }
        }

        return nil
    }

    private func observeAppModel(_ appModel: AppModel) {
        guard appModelObservation == nil else { return }

        appModelObservation = appModel.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.window?.toolbar?.validateVisibleItems()
            }
        }
    }

    @objc private func captureScreen() {
        appModel?.captureAndAsk()
    }

    @objc private func translateClipboard() {
        appModel?.translateClipboard()
    }

    @objc private func copyAnswer() {
        appModel?.copyLastAnswerToPasteboard()
    }

    @objc private func clearTranscript() {
        appModel?.clearTranscript()
    }

    @objc private func showSettings() {
        appModel?.showSettingsWindow()
    }

    private var currentWindowLevel: NSWindow.Level {
        isFloatingEnabled ? .floating : .normal
    }

    private func initialFrame() -> NSRect {
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(max(screenFrame.width * 0.42, 560), 700)
        let height = min(max(screenFrame.height * 0.65, 520), 760)
        let x = screenFrame.maxX - width - 24
        let y = screenFrame.midY - height / 2

        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private extension NSToolbarItem.Identifier {
    static let captureScreen = NSToolbarItem.Identifier("SasuCaptureScreen")
    static let translateClipboard = NSToolbarItem.Identifier("SasuTranslateClipboard")
    static let copyAnswer = NSToolbarItem.Identifier("SasuCopyAnswer")
    static let clearTranscript = NSToolbarItem.Identifier("SasuClearTranscript")
    static let settings = NSToolbarItem.Identifier("SasuSettings")
}
