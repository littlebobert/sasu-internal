import AppKit
import CoreGraphics
import Foundation
import OSLog

@MainActor
final class AppModel: ObservableObject {
    private static let logger = Logger(subsystem: "dev.sasu.Sasu", category: "AppModel")
    @Published var apiKeyInput = ""
    @Published private(set) var hasStoredAPIKey = false
    @Published private(set) var storedAPIKeyPreview = ""
    @Published var modelID: String {
        didSet { defaults.set(modelID, forKey: Self.modelIDKey) }
    }
    @Published var reasoningEffort: String {
        didSet { defaults.set(reasoningEffort, forKey: Self.reasoningEffortKey) }
    }
    @Published var serviceTier: String {
        didSet { defaults.set(serviceTier, forKey: Self.serviceTierKey) }
    }
    @Published var imageDetail: String {
        didSet { defaults.set(imageDetail, forKey: Self.imageDetailKey) }
    }
    @Published var selectedModelPresetID: String {
        didSet {
            defaults.set(selectedModelPresetID, forKey: Self.selectedModelPresetIDKey)
            applySelectedModelPreset()
        }
    }
    @Published var hotkeyKeyCode: UInt32 {
        didSet {
            defaults.set(Int(hotkeyKeyCode), forKey: Self.hotkeyKeyCodeKey)
            updateHotkeyRegistration()
        }
    }
    @Published var hotkeyModifiers: UInt32 {
        didSet {
            defaults.set(Int(hotkeyModifiers), forKey: Self.hotkeyModifiersKey)
            updateHotkeyRegistration()
        }
    }
    @Published var translateClipboardHotkeyKeyCode: UInt32 {
        didSet {
            defaults.set(Int(translateClipboardHotkeyKeyCode), forKey: Self.translateClipboardHotkeyKeyCodeKey)
            updateTranslateClipboardHotkeyRegistration()
        }
    }
    @Published var translateClipboardHotkeyModifiers: UInt32 {
        didSet {
            defaults.set(Int(translateClipboardHotkeyModifiers), forKey: Self.translateClipboardHotkeyModifiersKey)
            updateTranslateClipboardHotkeyRegistration()
        }
    }
    @Published private(set) var hotkeyDescription = HotkeyConfiguration.defaultConfiguration.displayName
    @Published private(set) var translateClipboardHotkeyDescription = HotkeyConfiguration.defaultTranslateClipboardConfiguration.displayName
    @Published private(set) var statusMessage = "Add your OpenAI API key, then press the hotkey or use Capture Screen."
    @Published private(set) var errorMessage: String?
    @Published private(set) var shouldOfferPermissionRelaunch = false
    @Published private(set) var isRequestInFlight = false
    @Published private(set) var isScreenshotPrepared = false
    @Published private(set) var screenshotPreviewImage: NSImage?
    @Published private(set) var lastResponse: AssistantResponse?
    @Published private(set) var currentHighlightSuggestion: HighlightSuggestion?
    @Published private(set) var isHighlightVisible = false
    @Published private(set) var transcriptMessages: [ChatTranscriptMessage] = []
    @Published var followUpText = ""
    @Published private(set) var querySelectionNonce = 0

    private static let modelIDKey = "modelID"
    private static let reasoningEffortKey = "reasoningEffort"
    private static let serviceTierKey = "serviceTier"
    private static let imageDetailKey = "imageDetail"
    private static let selectedModelPresetIDKey = "selectedModelPresetID"
    private static let hotkeyKeyCodeKey = "hotkeyKeyCode"
    private static let hotkeyModifiersKey = "hotkeyModifiers"
    private static let translateClipboardHotkeyKeyCodeKey = "translateClipboardHotkeyKeyCode"
    private static let translateClipboardHotkeyModifiersKey = "translateClipboardHotkeyModifiers"
    private static let hasCompletedFirstLaunchKey = "hasCompletedFirstLaunch"
    private static let shouldShowSettingsOnLaunchKey = "shouldShowSettingsOnLaunch"
    private static let settingsWindowPresentationID = "settings"
    private static let aboutWindowPresentationID = "about"
    private static let retiredModelAliases = [
        "gpt-5.5-high-fast"
    ]

    private let defaults: UserDefaults
    private let keychain: KeychainService
    private let screenshotService: ScreenshotService
    private let openAIClient: OpenAIClient
    private let highlightGroundingService: HighlightGroundingService
    private let clipboardTextService: ClipboardTextService
    private let answerWindowController: AnswerWindowController
    private let settingsWindowController: SettingsWindowController
    private let screenshotPreviewWindowController: ScreenshotPreviewWindowController
    private let highlightOverlayController: HighlightOverlayController
    private var hotkeyManager: HotkeyManager?
    private var translateClipboardHotkeyManager: HotkeyManager?
    private var lastScreenshot: ScreenshotPayload?
    private var currentRequestTask: Task<Void, Never>?
    private var highlightAutoHideTask: Task<Void, Never>?
    private var highlightGlobalClickMonitor: Any?
    private var highlightLocalClickMonitor: Any?
    private var shouldRestoreAnswerWindowAfterHighlight = false
    private var windowsHiddenForHighlight: [NSWindow] = []
    private var hasPresentedScreenRecordingPrimer = false
    private var appActivationObserver: NSObjectProtocol?
    private var attentionRequestID: Int?
    private var standardWindowPresentationIDs = Set<String>()

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainService = KeychainService(),
        screenshotService: ScreenshotService = ScreenshotService(),
        openAIClient: OpenAIClient = OpenAIClient(),
        highlightGroundingService: HighlightGroundingService = HighlightGroundingService(),
        clipboardTextService: ClipboardTextService = ClipboardTextService()
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.screenshotService = screenshotService
        self.openAIClient = openAIClient
        self.highlightGroundingService = highlightGroundingService
        self.clipboardTextService = clipboardTextService
        self.answerWindowController = AnswerWindowController()
        self.settingsWindowController = SettingsWindowController()
        self.screenshotPreviewWindowController = ScreenshotPreviewWindowController()
        self.highlightOverlayController = HighlightOverlayController()
        let savedModelID = defaults.string(forKey: Self.modelIDKey)
        let initialModelID: String
        if let savedModelID, !Self.retiredModelAliases.contains(savedModelID) {
            initialModelID = savedModelID
        } else {
            initialModelID = ModelPreset.gpt55HighFast.modelID
            defaults.set(ModelPreset.gpt55HighFast.modelID, forKey: Self.modelIDKey)
        }
        let initialReasoningEffort = defaults.string(forKey: Self.reasoningEffortKey) ?? ModelPreset.gpt55HighFast.reasoningEffort
        let initialServiceTier = defaults.string(forKey: Self.serviceTierKey) ?? ModelPreset.gpt55HighFast.serviceTier
        self.modelID = initialModelID
        self.reasoningEffort = initialReasoningEffort
        self.serviceTier = initialServiceTier
        self.imageDetail = defaults.string(forKey: Self.imageDetailKey) ?? ModelPreset.gpt55HighFast.imageDetail
        let savedPresetID = defaults.string(forKey: Self.selectedModelPresetIDKey)
        self.selectedModelPresetID = Self.availablePresetID(savedPresetID) ?? ModelPreset.matching(
            modelID: initialModelID,
            reasoningEffort: initialReasoningEffort,
            serviceTier: initialServiceTier
        ).id
        let savedHotkeyKeyCode = UInt32(defaults.integer(forKey: Self.hotkeyKeyCodeKey))
        self.hotkeyKeyCode = savedHotkeyKeyCode == 0
            ? HotkeyConfiguration.defaultConfiguration.keyCode
            : savedHotkeyKeyCode
        let savedHotkeyModifiers = UInt32(defaults.integer(forKey: Self.hotkeyModifiersKey))
        self.hotkeyModifiers = savedHotkeyModifiers == 0
            ? HotkeyConfiguration.defaultConfiguration.modifiers
            : savedHotkeyModifiers
        let savedTranslateClipboardHotkeyKeyCode = UInt32(defaults.integer(forKey: Self.translateClipboardHotkeyKeyCodeKey))
        self.translateClipboardHotkeyKeyCode = savedTranslateClipboardHotkeyKeyCode == 0
            ? HotkeyConfiguration.defaultTranslateClipboardConfiguration.keyCode
            : savedTranslateClipboardHotkeyKeyCode
        let savedTranslateClipboardHotkeyModifiers = UInt32(defaults.integer(forKey: Self.translateClipboardHotkeyModifiersKey))
        self.translateClipboardHotkeyModifiers = savedTranslateClipboardHotkeyModifiers == 0
            ? HotkeyConfiguration.defaultTranslateClipboardConfiguration.modifiers
            : savedTranslateClipboardHotkeyModifiers
        self.hotkeyDescription = hotkeyConfiguration.displayName
        self.translateClipboardHotkeyDescription = translateClipboardHotkeyConfiguration.displayName
        refreshStoredAPIKeyPreview()
        applySelectedModelPreset()
    }

    func start() {
        if hotkeyManager == nil {
            updateHotkeyRegistration()
        }
        if translateClipboardHotkeyManager == nil {
            updateTranslateClipboardHotkeyRegistration()
        }

        registerAppActivationObserverIfNeeded()
        presentScreenRecordingPrimerIfNeeded()
    }

    func showLaunchWindowIfNeeded() {
        let shouldRestoreSettings = defaults.bool(forKey: Self.shouldShowSettingsOnLaunchKey)
        defaults.set(true, forKey: Self.hasCompletedFirstLaunchKey)
        let shouldShowSettings = !hasStoredAPIKey || shouldRestoreSettings

        Task {
            // Let the app finish installing menu/activation state before presenting launch UI.
            try? await Task.sleep(nanoseconds: 100_000_000)
            await MainActor.run {
                if shouldShowSettings {
                    self.showSettingsWindowWithStandardOrdering()
                } else {
                    answerWindowController.show(appModel: self)
                }
            }
        }
    }

    func showSettingsWindow() {
        showSettingsWindowWithStandardOrdering()
        defaults.set(true, forKey: Self.shouldShowSettingsOnLaunchKey)
    }

    func showWindowForReopen() {
        if hasStoredAPIKey {
            answerWindowController.show(appModel: self)
        } else {
            showSettingsWindowWithStandardOrdering()
        }
    }

    func beginAboutWindowPresentation() {
        beginStandardWindowPresentation(Self.aboutWindowPresentationID)
    }

    func endAboutWindowPresentation() {
        endStandardWindowPresentation(Self.aboutWindowPresentationID)
    }

    private func showSettingsWindowWithStandardOrdering() {
        beginStandardWindowPresentation(Self.settingsWindowPresentationID)
        settingsWindowController.show(appModel: self) { [weak self] in
            self?.endStandardWindowPresentation(Self.settingsWindowPresentationID)
        }
    }

    private func beginStandardWindowPresentation(_ identifier: String) {
        standardWindowPresentationIDs.insert(identifier)
        answerWindowController.setFloatingEnabled(false)
    }

    private func endStandardWindowPresentation(_ identifier: String) {
        standardWindowPresentationIDs.remove(identifier)
        if standardWindowPresentationIDs.isEmpty {
            answerWindowController.setFloatingEnabled(true)
        }
    }

    func saveWindowStateForNextLaunch() {
        defaults.set(settingsWindowController.isVisible, forKey: Self.shouldShowSettingsOnLaunchKey)
    }

    func saveAPIKey() {
        let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            errorMessage = "Paste an OpenAI API key before saving."
            return
        }

        do {
            try keychain.saveAPIKey(trimmedKey)
            apiKeyInput = ""
            storedAPIKeyPreview = Self.apiKeyPreview(for: trimmedKey)
            hasStoredAPIKey = true
            errorMessage = nil
            statusMessage = "OpenAI API key saved in Keychain."
        } catch {
            errorMessage = "Could not save API key: \(error.localizedDescription)"
        }
    }

    func deleteAPIKey() {
        do {
            try keychain.deleteAPIKey()
            hasStoredAPIKey = false
            storedAPIKeyPreview = ""
            errorMessage = nil
            statusMessage = "OpenAI API key cleared."
        } catch {
            errorMessage = "Could not clear API key: \(error.localizedDescription)"
        }
    }

    private func refreshStoredAPIKeyPreview() {
        guard let apiKey = try? keychain.readAPIKey(), !apiKey.isEmpty else {
            hasStoredAPIKey = false
            storedAPIKeyPreview = ""
            return
        }

        hasStoredAPIKey = true
        storedAPIKeyPreview = Self.apiKeyPreview(for: apiKey)
    }

    private static func apiKeyPreview(for apiKey: String) -> String {
        "sk-...\(apiKey.suffix(4))"
    }

    func resetModelToDefault() {
        selectedModelPresetID = ModelPreset.gpt55HighFast.id
        applySelectedModelPreset()
        errorMessage = nil
        statusMessage = "Model reset to \(ModelPreset.gpt55HighFast.label)."
    }

    var selectedModelPreset: ModelPreset {
        ModelPreset.preset(id: selectedModelPresetID)
    }

    private func applySelectedModelPreset() {
        let preset = selectedModelPreset
        modelID = preset.modelID
        reasoningEffort = preset.reasoningEffort
        serviceTier = preset.serviceTier
        imageDetail = preset.imageDetail
    }

    private static func availablePresetID(_ presetID: String?) -> String? {
        guard let presetID else { return nil }
        return ModelPreset.all.contains { $0.id == presetID } ? presetID : nil
    }

    func setHotkeyModifier(_ modifier: UInt32, enabled: Bool) {
        if enabled {
            hotkeyModifiers |= modifier
        } else {
            let updatedModifiers = hotkeyModifiers & ~modifier
            guard updatedModifiers != 0 else {
                errorMessage = "Choose at least one modifier for the global hotkey."
                return
            }

            hotkeyModifiers = updatedModifiers
        }
    }

    func resetHotkeyToDefault() {
        hotkeyKeyCode = HotkeyConfiguration.defaultConfiguration.keyCode
        hotkeyModifiers = HotkeyConfiguration.defaultConfiguration.modifiers
        statusMessage = "Hotkey reset to \(hotkeyDescription)."
    }

    func setTranslateClipboardHotkeyModifier(_ modifier: UInt32, enabled: Bool) {
        if enabled {
            translateClipboardHotkeyModifiers |= modifier
        } else {
            let updatedModifiers = translateClipboardHotkeyModifiers & ~modifier
            guard updatedModifiers != 0 else {
                errorMessage = "Choose at least one modifier for the Translate Clipboard hotkey."
                return
            }

            translateClipboardHotkeyModifiers = updatedModifiers
        }
    }

    func resetTranslateClipboardHotkeyToDefault() {
        translateClipboardHotkeyKeyCode = HotkeyConfiguration.defaultTranslateClipboardConfiguration.keyCode
        translateClipboardHotkeyModifiers = HotkeyConfiguration.defaultTranslateClipboardConfiguration.modifiers
        statusMessage = "Translate Clipboard hotkey reset to \(translateClipboardHotkeyDescription)."
    }

    func captureAndAsk() {
        guard !isRequestInFlight else { return }

        currentRequestTask = Task {
            await prepareScreenshotForQuery()
        }
    }

    func translateClipboard() {
        guard !isRequestInFlight else { return }

        currentRequestTask = Task {
            await runTranslateClipboard()
        }
    }

    func sendFollowUp() {
        let followUp = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !followUp.isEmpty else { return }
        guard lastScreenshot != nil else {
            errorMessage = "Capture the screen before sending a follow-up."
            return
        }

        followUpText = ""
        currentRequestTask = Task {
            await runCapture(prompt: followUp, reuseLastScreenshot: true)
        }
    }

    func stopCurrentRequest() {
        guard isRequestInFlight else { return }

        currentRequestTask?.cancel()
        currentRequestTask = nil
        isRequestInFlight = false
        statusMessage = "Request stopped."
        errorMessage = nil
        transcriptMessages.append(ChatTranscriptMessage(role: .error, text: "Request stopped."))
        Self.logger.info("User cancelled current request.")
    }

    func copyLastAnswerToPasteboard() {
        guard let text = lastResponse?.text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = "Answer copied to clipboard."
    }

    func copyTranscriptToPasteboard() {
        let transcript = transcriptMessages
            .map { "\($0.role.rawValue):\n\($0.text)" }
            .joined(separator: "\n\n")
        guard !transcript.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
        statusMessage = "Transcript copied to clipboard."
    }

    func clearTranscript() {
        transcriptMessages.removeAll()
        lastResponse = nil
        errorMessage = nil
        shouldOfferPermissionRelaunch = false
        currentHighlightSuggestion = nil
        hideHighlight()
        statusMessage = "Transcript cleared."
    }

    func clearPreparedScreenshot() {
        lastScreenshot = nil
        screenshotPreviewImage = nil
        isScreenshotPrepared = false
        currentHighlightSuggestion = nil
        hideHighlight()
    }

    func showScreenshotWindow(imageData: Data) {
        guard let image = NSImage(data: imageData) else {
            errorMessage = "Could not open screenshot preview."
            return
        }

        screenshotPreviewWindowController.show(image: image)
    }

    func showHighlight() {
        guard let currentHighlightSuggestion, let lastScreenshot else { return }
        highlightAutoHideTask?.cancel()
        windowsHiddenForHighlight = Self.hideVisibleSasuWindowsForCapture()
        shouldRestoreAnswerWindowAfterHighlight = true
        startHighlightClickMonitoring()
        highlightOverlayController.show(
            highlight: currentHighlightSuggestion,
            screenshot: lastScreenshot
        )
        isHighlightVisible = true
        highlightAutoHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.hideHighlight(restoreAnswerWindow: true)
            }
        }
    }

    func hideHighlight(
        restoreAnswerWindow: Bool = false,
        restoreWhenAppActivates: Bool = false
    ) {
        highlightAutoHideTask?.cancel()
        highlightAutoHideTask = nil
        stopHighlightClickMonitoring()
        highlightOverlayController.hide()
        isHighlightVisible = false

        if restoreAnswerWindow, shouldRestoreAnswerWindowAfterHighlight {
            shouldRestoreAnswerWindowAfterHighlight = false
            restoreWindowsHiddenForHighlight()
        } else if !restoreAnswerWindow {
            if restoreWhenAppActivates {
                shouldRestoreAnswerWindowAfterHighlight = true
            } else {
                shouldRestoreAnswerWindowAfterHighlight = false
                windowsHiddenForHighlight.removeAll()
            }
        }
    }

    private func registerAppActivationObserverIfNeeded() {
        guard appActivationObserver == nil else { return }

        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.cancelUserAttentionRequestIfNeeded()
                self?.restoreHighlightWindowsAfterUserReturn()
            }
        }
    }

    private func restoreHighlightWindowsAfterUserReturn() {
        guard !isHighlightVisible else { return }
        guard shouldRestoreAnswerWindowAfterHighlight else { return }

        shouldRestoreAnswerWindowAfterHighlight = false
        restoreWindowsHiddenForHighlight()
    }

    private func restoreWindowsHiddenForHighlight() {
        if windowsHiddenForHighlight.isEmpty {
            answerWindowController.show(appModel: self)
        } else {
            Self.restoreWindows(windowsHiddenForHighlight)
            NSApp.activate(ignoringOtherApps: true)
        }

        windowsHiddenForHighlight.removeAll()
    }

    private func startHighlightClickMonitoring() {
        stopHighlightClickMonitoring()

        let eventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        highlightGlobalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] _ in
            Task { @MainActor in
                self?.hideHighlight(restoreWhenAppActivates: true)
            }
        }
        highlightLocalClickMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            Task { @MainActor in
                self?.hideHighlight(restoreWhenAppActivates: true)
            }
            return event
        }
    }

    private func stopHighlightClickMonitoring() {
        if let highlightGlobalClickMonitor {
            NSEvent.removeMonitor(highlightGlobalClickMonitor)
            self.highlightGlobalClickMonitor = nil
        }

        if let highlightLocalClickMonitor {
            NSEvent.removeMonitor(highlightLocalClickMonitor)
            self.highlightLocalClickMonitor = nil
        }
    }

    func openScreenRecordingSettings() {
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"),
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")
        ].compactMap { $0 }

        statusMessage = "Opened Screen Recording settings. Enable Sasu, then relaunch Sasu."

        for url in urls where Self.openSystemSettings(url: url) {
            Task { @MainActor in
                for delay in [250_000_000, 750_000_000, 1_500_000_000] {
                    try? await Task.sleep(nanoseconds: UInt64(delay))
                    if Self.activateSystemSettings() {
                        break
                    }
                }
            }
            return
        }

        errorMessage = "Open System Settings > Privacy & Security > Screen Recording, then enable Sasu."
    }

    private func presentScreenRecordingPrimerIfNeeded() {
        guard !hasPresentedScreenRecordingPrimer else { return }
        guard !CGPreflightScreenCaptureAccess() else { return }

        hasPresentedScreenRecordingPrimer = true
        Task { @MainActor in
            // Let the Settings window finish appearing before presenting the modal primer.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !CGPreflightScreenCaptureAccess() else { return }

            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Sasu Needs Screen Recording"
            alert.informativeText = """
            Sasu captures your screen only when you press the hotkey or Capture Screen, then sends that screenshot to OpenAI with your question.

            macOS requires Screen Recording permission before Sasu can see the page or app you want help with.
            """
            alert.addButton(withTitle: "Accept Screen Recording")
            alert.addButton(withTitle: "Quit")

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                requestScreenRecordingPermission()
            default:
                NSApp.terminate(nil)
            }
        }
    }

    private func requestScreenRecordingPermission() {
        statusMessage = "Waiting for Screen Recording permission..."
        _ = CGRequestScreenCaptureAccess()

        if CGPreflightScreenCaptureAccess() {
            statusMessage = "Screen Recording permission granted. Press \(hotkeyDescription) or use Capture Screen."
        } else {
            statusMessage = "Approve the macOS Screen Recording prompt. If you do not see it, use Open Screen Recording Settings."
        }
    }

    func relaunchSasu() {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            errorMessage = "Quit this process and launch Sasu from Build/Sasu.app so macOS applies Screen Recording permission to the app bundle."
            return
        }

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [
                "-c",
                "sleep 0.5; /usr/bin/open \(Self.shellQuoted(bundleURL.path))"
            ]
            try process.run()
            NSApp.terminate(nil)
        } catch {
            errorMessage = "Could not relaunch Sasu automatically: \(error.localizedDescription)"
        }
    }

    private var hotkeyConfiguration: HotkeyConfiguration {
        HotkeyConfiguration(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }

    private var translateClipboardHotkeyConfiguration: HotkeyConfiguration {
        HotkeyConfiguration(
            keyCode: translateClipboardHotkeyKeyCode,
            modifiers: translateClipboardHotkeyModifiers
        )
    }

    private func updateHotkeyRegistration() {
        hotkeyManager?.unregister()
        hotkeyManager = nil

        hotkeyDescription = hotkeyConfiguration.displayName
        let manager = HotkeyManager(configuration: hotkeyConfiguration, identifier: 1) { [weak self] in
            Task { @MainActor in
                self?.captureAndAsk()
            }
        }

        do {
            try manager.register()
            hotkeyManager = manager
            errorMessage = nil
            statusMessage = "Ready. Press \(hotkeyDescription) to capture or \(translateClipboardHotkeyDescription) to translate clipboard."
        } catch {
            errorMessage = "Could not register \(hotkeyDescription): \(error.localizedDescription)"
            statusMessage = "Use Capture Screen from the app while the hotkey is unavailable."
        }
    }

    private func updateTranslateClipboardHotkeyRegistration() {
        translateClipboardHotkeyManager?.unregister()
        translateClipboardHotkeyManager = nil

        translateClipboardHotkeyDescription = translateClipboardHotkeyConfiguration.displayName
        let manager = HotkeyManager(configuration: translateClipboardHotkeyConfiguration, identifier: 2) { [weak self] in
            Task { @MainActor in
                self?.translateClipboard()
            }
        }

        do {
            try manager.register()
            translateClipboardHotkeyManager = manager
            errorMessage = nil
            statusMessage = "Ready. Press \(hotkeyDescription) to capture or \(translateClipboardHotkeyDescription) to translate clipboard."
        } catch {
            errorMessage = "Could not register \(translateClipboardHotkeyDescription): \(error.localizedDescription)"
            statusMessage = "Use Translate Clipboard from the app while the hotkey is unavailable."
        }
    }

    private func prepareScreenshotForQuery() async {
        isRequestInFlight = true
        errorMessage = nil
        shouldOfferPermissionRelaunch = false
        statusMessage = "Capturing screen..."
        Self.logger.info("Preparing screenshot for user query.")

        do {
            let hiddenWindows = Self.hideVisibleSasuWindowsForCapture()
            if !hiddenWindows.isEmpty {
                try await Task.sleep(nanoseconds: 150_000_000)
            }
            try Task.checkCancellation()
            defer {
                Self.restoreWindows(hiddenWindows)
            }

            let screenshot = try await screenshotService.captureMainDisplay()
            let isFirstScreenshot = transcriptMessages.isEmpty
            lastScreenshot = screenshot
            screenshotPreviewImage = NSImage(data: screenshot.pngData)
            isScreenshotPrepared = true
            appendScreenshotMessage(for: screenshot)
            followUpText = isFirstScreenshot ? "Explain this" : "What now?"
            querySelectionNonce += 1
            currentHighlightSuggestion = nil
            hideHighlight()
            statusMessage = "Screenshot ready. Type your question and press Send."
            Self.logger.info("Prepared screenshot. bytes=\(screenshot.pngData.count), pixelWidth=\(Int(screenshot.pixelSize.width)), pixelHeight=\(Int(screenshot.pixelSize.height))")
        } catch is CancellationError {
            statusMessage = "Capture stopped."
            errorMessage = nil
            Self.logger.info("Screenshot preparation cancelled.")
        } catch {
            errorMessage = error.localizedDescription
            shouldOfferPermissionRelaunch = (error as? ScreenshotError) == .permissionDenied
            statusMessage = "Something went wrong."
            transcriptMessages.append(ChatTranscriptMessage(role: .error, text: error.localizedDescription))
            Self.logger.error("Screenshot preparation failed: \(error.localizedDescription, privacy: .public)")
        }

        isRequestInFlight = false
        currentRequestTask = nil
        answerWindowController.show(appModel: self)
    }

    private func runTranslateClipboard() async {
        isRequestInFlight = true
        errorMessage = nil
        shouldOfferPermissionRelaunch = false
        currentHighlightSuggestion = nil
        hideHighlight()
        statusMessage = "Reading clipboard..."
        Self.logger.info("Starting clipboard translation flow. model=\(self.modelID, privacy: .public), reasoning=\(self.reasoningEffort, privacy: .public), serviceTier=\(self.serviceTier, privacy: .public)")

        do {
            try Task.checkCancellation()
            let sourceText = try clipboardTextService.readText()
            let conversationContext = transcriptContextForRequest()
            transcriptMessages.append(ChatTranscriptMessage(role: .user, text: "Clipboard text: \(sourceText)"))

            try Task.checkCancellation()
            guard let apiKey = try keychain.readAPIKey(), !apiKey.isEmpty else {
                throw AppError.missingAPIKey
            }

            statusMessage = "Translating clipboard..."
            answerWindowController.show(appModel: self)
            let answer = try await openAIClient.translateClipboardText(
                apiKey: apiKey,
                modelID: modelID,
                reasoningEffort: reasoningEffort,
                serviceTier: serviceTier,
                sourceText: sourceText,
                conversationContext: conversationContext
            )
            try Task.checkCancellation()
            let translation = "Translation: \(Self.normalizedTranslationText(answer))"

            lastResponse = AssistantResponse(
                text: translation,
                prompt: "Translate clipboard",
                actionSuggestion: nil
            )
            transcriptMessages.append(ChatTranscriptMessage(role: .assistant, text: translation))
            statusMessage = "Clipboard translation ready."
            Self.logger.info("Clipboard translation ready. sourceCharacters=\(sourceText.count), answerCharacters=\(translation.count)")
        } catch is CancellationError {
            statusMessage = "Request stopped."
            errorMessage = nil
            Self.logger.info("Clipboard translation cancelled.")
        } catch {
            errorMessage = error.localizedDescription
            transcriptMessages.append(ChatTranscriptMessage(role: .error, text: error.localizedDescription))
            statusMessage = "Something went wrong."
            Self.logger.error("Clipboard translation failed: \(error.localizedDescription, privacy: .public)")
        }

        isRequestInFlight = false
        currentRequestTask = nil
        let shouldActivateAnswerWindow = NSApp.isActive
        answerWindowController.show(appModel: self, activate: shouldActivateAnswerWindow)
        if !shouldActivateAnswerWindow {
            requestUserAttentionIfNeeded()
        }
    }

    private static func normalizedTranslationText(_ text: String) -> String {
        TextSpacingRepair.repairMissingSpaces(
            in: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func runCapture(prompt: String, reuseLastScreenshot: Bool = false) async {
        isRequestInFlight = true
        errorMessage = nil
        shouldOfferPermissionRelaunch = false
        statusMessage = reuseLastScreenshot ? "Sending follow-up..." : "Capturing screen..."
        Self.logger.info("Starting capture flow. reuseLastScreenshot=\(reuseLastScreenshot), model=\(self.modelID, privacy: .public), reasoning=\(self.reasoningEffort, privacy: .public), serviceTier=\(self.serviceTier, privacy: .public), imageDetail=\(self.imageDetail, privacy: .public)")
        let conversationContext = transcriptContextForRequest()
        transcriptMessages.append(ChatTranscriptMessage(role: .user, text: prompt))

        do {
            try Task.checkCancellation()
            guard let apiKey = try keychain.readAPIKey(), !apiKey.isEmpty else {
                throw AppError.missingAPIKey
            }

            let screenshot: ScreenshotPayload
            if reuseLastScreenshot, let existingScreenshot = lastScreenshot {
                screenshot = existingScreenshot
            } else {
                let hiddenWindows = Self.hideVisibleSasuWindowsForCapture()
                if !hiddenWindows.isEmpty {
                    try await Task.sleep(nanoseconds: 150_000_000)
                }
                try Task.checkCancellation()
                defer {
                    Self.restoreWindows(hiddenWindows)
                }

                screenshot = try await screenshotService.captureMainDisplay()
                lastScreenshot = screenshot
                screenshotPreviewImage = NSImage(data: screenshot.pngData)
                isScreenshotPrepared = true
                appendScreenshotMessage(for: screenshot)
            }
            try Task.checkCancellation()
            Self.logger.info("Screenshot ready. bytes=\(screenshot.pngData.count), pixelWidth=\(Int(screenshot.pixelSize.width)), pixelHeight=\(Int(screenshot.pixelSize.height))")

            statusMessage = "Asking OpenAI..."
            answerWindowController.show(appModel: self)
            let result = try await openAIClient.askAboutScreenshot(
                apiKey: apiKey,
                modelID: modelID,
                reasoningEffort: reasoningEffort,
                serviceTier: serviceTier,
                imageDetail: imageDetail,
                prompt: prompt,
                screenshot: screenshot,
                conversationContext: conversationContext
            )
            try Task.checkCancellation()
            let actionSuggestion = await groundedSuggestion(
                result.actionSuggestion,
                screenshot: screenshot
            )
            try Task.checkCancellation()

            lastResponse = AssistantResponse(
                text: result.answer,
                prompt: prompt,
                actionSuggestion: actionSuggestion
            )
            currentHighlightSuggestion = actionSuggestion
            hideHighlight()
            transcriptMessages.append(
                ChatTranscriptMessage(
                    role: .assistant,
                    text: result.answer,
                    actionSuggestion: actionSuggestion
                )
            )
            statusMessage = "Answer ready."
            Self.logger.info("OpenAI answer ready. characters=\(result.answer.count), hasHighlight=\(actionSuggestion != nil)")
        } catch is CancellationError {
            statusMessage = "Request stopped."
            errorMessage = nil
            Self.logger.info("Capture flow cancelled.")
        } catch {
            errorMessage = error.localizedDescription
            transcriptMessages.append(ChatTranscriptMessage(role: .error, text: error.localizedDescription))
            shouldOfferPermissionRelaunch = (error as? ScreenshotError) == .permissionDenied
            statusMessage = "Something went wrong."
            Self.logger.error("Capture flow failed: \(error.localizedDescription, privacy: .public)")
        }

        isRequestInFlight = false
        currentRequestTask = nil
        let shouldActivateAnswerWindow = NSApp.isActive
        answerWindowController.show(appModel: self, activate: shouldActivateAnswerWindow)
        if !shouldActivateAnswerWindow {
            requestUserAttentionIfNeeded()
        }
    }

    private func appendScreenshotMessage(for screenshot: ScreenshotPayload) {
        transcriptMessages.append(
            ChatTranscriptMessage(
                role: .screenshot,
                text: "\(Int(screenshot.pixelSize.width)) x \(Int(screenshot.pixelSize.height))",
                imageData: screenshot.pngData
            )
        )
    }

    private func transcriptContextForRequest() -> String? {
        let messages = transcriptMessages
            .filter { $0.role != .error && $0.role != .screenshot }
            .suffix(10)
            .map { "\($0.role.rawValue): \($0.text)" }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !messages.isEmpty else { return nil }

        if messages.count <= 4_000 {
            return messages
        }

        return String(messages.suffix(4_000))
    }

    private func groundedSuggestion(
        _ suggestion: HighlightSuggestion?,
        screenshot: ScreenshotPayload
    ) async -> HighlightSuggestion? {
        guard let suggestion else { return nil }
        return await highlightGroundingService.groundedSuggestion(
            suggestion,
            in: screenshot
        )
    }

    private func requestUserAttentionIfNeeded() {
        guard !NSApp.isActive else { return }
        cancelUserAttentionRequestIfNeeded()
        attentionRequestID = NSApp.requestUserAttention(.criticalRequest)
    }

    private func cancelUserAttentionRequestIfNeeded() {
        if let attentionRequestID {
            NSApp.cancelUserAttentionRequest(attentionRequestID)
            self.attentionRequestID = nil
        }
    }

    private static func hideVisibleSasuWindowsForCapture() -> [NSWindow] {
        let windowsToHide = NSApp.windows.filter { window in
            window.isVisible && !window.isMiniaturized
        }

        windowsToHide.forEach { $0.orderOut(nil) }
        return windowsToHide
    }

    private static func restoreWindows(_ windows: [NSWindow]) {
        windows.forEach { $0.orderFront(nil) }
    }

    private static func openSystemSettings(url: URL) -> Bool {
        guard let applicationURL = systemSettingsApplicationURL() else {
            return NSWorkspace.shared.open(url)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: applicationURL,
            configuration: configuration,
            completionHandler: nil
        )
        return true
    }

    private static func systemSettingsApplicationURL() -> URL? {
        let bundleIdentifiers = [
            "com.apple.SystemSettings",
            "com.apple.systempreferences"
        ]

        for bundleIdentifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return url
            }
        }

        return nil
    }

    private static func activateSystemSettings() -> Bool {
        let bundleIdentifiers = [
            "com.apple.SystemSettings",
            "com.apple.systempreferences"
        ]

        for bundleIdentifier in bundleIdentifiers {
            guard let app = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .first
            else {
                continue
            }

            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return true
        }

        return false
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

enum AppError: LocalizedError {
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your OpenAI API key in Sasu before capturing the screen."
        }
    }
}
