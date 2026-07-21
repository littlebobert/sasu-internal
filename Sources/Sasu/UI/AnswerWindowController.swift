import AppKit
import Combine
import SwiftUI

@MainActor
final class AnswerWindowController: NSObject, NSToolbarDelegate, NSToolbarItemValidation {
    private var window: NSPanel?
    private weak var appModel: AppModel?
    private var appModelObservation: AnyCancellable?
    private var onboardingObservation: AnyCancellable?
    private var isFloatingEnabled = true

    func show(appModel: AppModel, activate: Bool = true) {
        self.appModel = appModel
        observeAppModel(appModel)

        if window == nil {
            window = makeWindow(appModel: appModel)
        }

        window?.level = currentWindowLevel
        resizeForOnboardingIfNeeded(appModel: appModel)
        guard activate else { return }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setFloatingEnabled(_ isEnabled: Bool) {
        isFloatingEnabled = isEnabled
        window?.level = currentWindowLevel
    }

    func temporarilyDisableFloating(for duration: TimeInterval = 2.0) {
        setFloatingEnabled(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self else { return }
            self.setFloatingEnabled(true)
        }
    }

    func hide() {
        window?.orderOut(nil)
    }

    var isVisible: Bool {
        window?.isVisible == true
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
                label: String(localized: "Capture & Ask"),
                symbolNames: ["camera.viewfinder", "rectangle.dashed"],
                symbolStyle: .accent,
                action: #selector(captureScreen)
            )
        case .translateSelection:
            return toolbarItem(
                identifier: itemIdentifier,
                label: String(localized: "Translate Selection"),
                symbolNames: ["translate", "character.book.closed", "textformat"],
                symbolStyle: .accent,
                action: #selector(translateSelection)
            )
        case .translateAndReplace:
            return toolbarItem(
                identifier: itemIdentifier,
                label: String(localized: "Translate & Replace"),
                symbolNames: ["character.cursor.ibeam", "text.cursor"],
                symbolStyle: .accent,
                action: #selector(translateAndReplace)
            )
        case .copyAnswer:
            return toolbarItem(
                identifier: itemIdentifier,
                label: String(localized: "Copy Answer"),
                symbolNames: ["doc.on.doc", "doc.on.clipboard"],
                symbolStyle: .accent,
                action: #selector(copyAnswer)
            )
        case .clearTranscript:
            return toolbarItem(
                identifier: itemIdentifier,
                label: String(localized: "Clear"),
                symbolNames: ["trash"],
                symbolStyle: .multicolor,
                action: #selector(clearTranscript)
            )
        case .settings:
            return toolbarItem(
                identifier: itemIdentifier,
                label: String(localized: "Settings"),
                symbolNames: ["gear", "gearshape"],
                symbolStyle: .multicolor,
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
            .translateSelection,
            .translateAndReplace,
            .copyAnswer,
            .clearTranscript,
            .settings
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .captureScreen,
            .translateSelection,
            .translateAndReplace,
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
        case .captureScreen, .translateSelection, .translateAndReplace:
            return !appModel.isRequestInFlight && !appModel.isFirstLaunchOnboardingVisible
        case .copyAnswer:
            return appModel.lastResponse != nil
        case .clearTranscript:
            return !appModel.transcriptMessages.isEmpty && !appModel.isRequestInFlight && !appModel.isFirstLaunchOnboardingVisible
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

        panel.title = String(localized: "Transcript")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = false
        panel.isReleasedWhenClosed = false
        panel.toolbar = makeToolbar()
        panel.toolbar?.displayMode = .labelOnly
        panel.toolbar?.sizeMode = .regular
        panel.toolbarStyle = .unified
        panel.contentView = NSHostingView(
            rootView: AnswerPanelView()
                .environmentObject(appModel)
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationActivationChanged(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: NSApp
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationActivationChanged(_:)),
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )

        return panel
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "SasuTranscriptToolbarV2")
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
        symbolStyle: ToolbarSymbolStyle,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = Self.symbolImage(named: symbolNames, style: symbolStyle)
        item.target = self
        item.action = action
        return item
    }

    private enum ToolbarSymbolStyle {
        case multicolor
        case accent
    }

    private static let toolbarSymbolConfiguration = NSImage.SymbolConfiguration(
        pointSize: 15,
        weight: .regular
    )

    private static func symbolImage(named symbolNames: [String], style: ToolbarSymbolStyle) -> NSImage? {
        for symbolName in symbolNames {
            guard let image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: nil
            ) else {
                continue
            }

            let configuration: NSImage.SymbolConfiguration
            switch style {
            case .multicolor:
                configuration = toolbarSymbolConfiguration.applying(.preferringMulticolor())
            case .accent:
                configuration = toolbarSymbolConfiguration.applying(
                    NSImage.SymbolConfiguration(paletteColors: [NSColor.controlAccentColor])
                )
            }

            guard let configuredImage = image.withSymbolConfiguration(configuration) else {
                continue
            }

            configuredImage.isTemplate = false
            return configuredImage
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

        onboardingObservation = Publishers.Merge(
            appModel.$isFirstLaunchOnboardingVisible.map { _ in () },
            appModel.$isOnboardingGuidanceVisible.map { _ in () }
        )
            .sink { [weak self, weak appModel] _ in
                DispatchQueue.main.async {
                    guard let appModel else { return }
                    self?.resizeForOnboardingIfNeeded(appModel: appModel)
                }
            }
    }

    private func resizeForOnboardingIfNeeded(appModel: AppModel) {
        guard appModel.isFirstLaunchOnboardingVisible, let window else { return }

        window.contentView?.layoutSubtreeIfNeeded()
        let fittingSize = window.contentView?.fittingSize ?? NSSize(width: 620, height: 400)
        let contentSize = NSSize(
            width: min(max(fittingSize.width, 620), 760),
            height: min(max(fittingSize.height, 390), 560)
        )
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        if let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            frame.origin.x = visibleFrame.midX - frame.width / 2
            frame.origin.y = visibleFrame.midY - frame.height / 2
        } else {
            frame.origin.x = window.frame.midX - frame.width / 2
            frame.origin.y = window.frame.midY - frame.height / 2
        }

        window.setFrame(frame, display: true, animate: false)
    }

    @objc private func captureScreen() {
        appModel?.captureAndAsk()
    }

    @objc private func translateSelection() {
        appModel?.translateVisibleSelection()
    }

    @objc private func translateAndReplace() {
        appModel?.translateAndReplaceSelection()
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

    @objc private func applicationActivationChanged(_ notification: Notification) {
        window?.level = currentWindowLevel
    }

    private var currentWindowLevel: NSWindow.Level {
        isFloatingEnabled && NSApp.isActive ? .floating : .normal
    }

    private func initialFrame() -> NSRect {
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(max(screenFrame.width * 0.42, 560), 700)
        let height = min(max(screenFrame.height * 0.42, 360), 520)
        let x = screenFrame.midX - width / 2
        let y = screenFrame.midY - height / 2

        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private extension NSToolbarItem.Identifier {
    static let captureScreen = NSToolbarItem.Identifier("SasuCaptureScreen")
    static let translateSelection = NSToolbarItem.Identifier("SasuTranslateClipboard")
    static let translateAndReplace = NSToolbarItem.Identifier("SasuTranslateAndReplace")
    static let copyAnswer = NSToolbarItem.Identifier("SasuCopyAnswer")
    static let clearTranscript = NSToolbarItem.Identifier("SasuClearTranscript")
    static let settings = NSToolbarItem.Identifier("SasuSettings")
}
