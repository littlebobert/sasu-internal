import AppKit
import CoreGraphics
import Foundation
import OSLog

@MainActor
final class AppModel: ObservableObject {
    private static let logger = Logger(subsystem: "dev.sasu.Sasu", category: "AppModel")
    @Published var accessMode: AccessMode {
        didSet { defaults.set(accessMode.rawValue, forKey: Self.accessModeKey) }
    }
    @Published var inviteCodeInput = ""
    @Published var backendBaseURLInput: String {
        didSet { defaults.set(backendBaseURLInput, forKey: Self.backendBaseURLKey) }
    }
    @Published private(set) var hasStoredBackendAccessToken = false
    @Published private(set) var backendAccessLabel = ""
    @Published private(set) var backendAccessTokenPreview = ""
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
    @Published var automaticallyIncludeSafariPageContent: Bool {
        didSet { defaults.set(automaticallyIncludeSafariPageContent, forKey: Self.automaticallyIncludeSafariPageContentKey) }
    }
    @Published var translationLanguagePair: TranslationLanguagePair {
        didSet { defaults.set(translationLanguagePair.rawValue, forKey: Self.translationLanguagePairKey) }
    }
    @Published var transcriptTextSize: Double {
        didSet {
            let clampedSize = Self.clampedTranscriptTextSize(transcriptTextSize)
            guard transcriptTextSize == clampedSize else {
                transcriptTextSize = clampedSize
                return
            }

            defaults.set(transcriptTextSize, forKey: Self.transcriptTextSizeKey)
        }
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
    @Published var translateSelectionHotkeyKeyCode: UInt32 {
        didSet {
            defaults.set(Int(translateSelectionHotkeyKeyCode), forKey: Self.translateSelectionHotkeyKeyCodeKey)
            updateTranslateSelectionHotkeyRegistration()
        }
    }
    @Published var translateSelectionHotkeyModifiers: UInt32 {
        didSet {
            defaults.set(Int(translateSelectionHotkeyModifiers), forKey: Self.translateSelectionHotkeyModifiersKey)
            updateTranslateSelectionHotkeyRegistration()
        }
    }
    @Published private(set) var hotkeyDescription = HotkeyConfiguration.defaultConfiguration.displayName
    @Published private(set) var translateClipboardHotkeyDescription = HotkeyConfiguration.defaultTranslateClipboardConfiguration.displayName
    @Published private(set) var translateSelectionHotkeyDescription = HotkeyConfiguration.defaultTranslateSelectionConfiguration.displayName
    @Published private(set) var statusMessage = "Set up invite access or add your OpenAI API key, then press the hotkey or use Capture Screen."
    @Published private(set) var errorMessage: String?
    @Published private(set) var shouldOfferPermissionRelaunch = false
    @Published private(set) var shouldOfferAccessibilityRelaunch = false
    @Published private(set) var hasAccessibilityAccess = false
    @Published private(set) var isRequestInFlight = false
    @Published private(set) var isScreenshotPrepared = false
    @Published private(set) var screenshotPreviewImage: NSImage?
    @Published private(set) var lastResponse: AssistantResponse?
    @Published private(set) var currentHighlightSuggestion: HighlightSuggestion?
    @Published private(set) var isHighlightVisible = false
    @Published private(set) var isFirstLaunchOnboardingVisible = false
    @Published private(set) var isOnboardingGuidanceVisible = false
    @Published private(set) var transcriptMessages: [ChatTranscriptMessage] = []
    @Published var followUpText = ""
    @Published private(set) var querySelectionNonce = 0

    var transcriptFontSize: CGFloat {
        CGFloat(transcriptTextSize)
    }

    private static let accessModeKey = "accessMode"
    private static let backendBaseURLKey = "backendBaseURL"
    private static let backendAccessLabelKey = "backendAccessLabel"
    private static let modelIDKey = "modelID"
    private static let reasoningEffortKey = "reasoningEffort"
    private static let serviceTierKey = "serviceTier"
    private static let imageDetailKey = "imageDetail"
    private static let automaticallyIncludeSafariPageContentKey = "automaticallyIncludeSafariPageContent"
    private static let translationLanguagePairKey = "translationLanguagePair"
    private static let transcriptTextSizeKey = "transcriptTextSize"
    private static let hasAnsweredSafariPageCapturePrimerKey = "hasAnsweredSafariPageCapturePrimer"
    private static let safariPageSendConfirmationCharacterThreshold = 8_000
    private static let selectedModelPresetIDKey = "selectedModelPresetID"
    private static let hotkeyKeyCodeKey = "hotkeyKeyCode"
    private static let hotkeyModifiersKey = "hotkeyModifiers"
    private static let translateClipboardHotkeyKeyCodeKey = "translateClipboardHotkeyKeyCode"
    private static let translateClipboardHotkeyModifiersKey = "translateClipboardHotkeyModifiers"
    private static let translateSelectionHotkeyKeyCodeKey = "translateSelectionHotkeyKeyCode"
    private static let translateSelectionHotkeyModifiersKey = "translateSelectionHotkeyModifiers"
    private static let hasCompletedFirstLaunchKey = "hasCompletedFirstLaunch"
    private static let hasCompletedFirstLaunchOnboardingKey = "hasCompletedFirstLaunchOnboarding"
    private static let shouldShowSettingsOnLaunchKey = "shouldShowSettingsOnLaunch"
    private static let settingsWindowPresentationID = "settings"
    private static let aboutWindowPresentationID = "about"
    private static let screenshotPreviewWindowPresentationID = "screenshot-preview"
    private static let retiredModelAliases = [
        "gpt-5.5-high-fast",
        "gpt-5.5"
    ]
    static let defaultTranscriptTextSize = 13.0
    static let minimumTranscriptTextSize = 11.0
    static let maximumTranscriptTextSize = 24.0
    static let transcriptTextSizeStep = 1.0
    private static var defaultBackendBaseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "SASUBackendBaseURL") as? String ?? "https://sasu-backend-f1fe990b2452.herokuapp.com"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainService
    private let screenshotService: ScreenshotService
    private let openAIClient: OpenAIClient
    private let backendClient: BackendClient
    private let highlightGroundingService: HighlightGroundingService
    private let clipboardTextService: ClipboardTextService
    private let selectionAutomationService: SelectionAutomationService
    private let safariPageCaptureService: SafariPageCaptureService
    private let answerWindowController: AnswerWindowController
    private let settingsWindowController: SettingsWindowController
    private let screenshotPreviewWindowController: ScreenshotPreviewWindowController
    private let highlightOverlayController: HighlightOverlayController
    private let cursorProgressOverlayController: CursorProgressOverlayController
    private var hotkeyManager: HotkeyManager?
    private var translateClipboardHotkeyManager: HotkeyManager?
    private var translateSelectionHotkeyManager: HotkeyManager?
    private var lastScreenshot: ScreenshotPayload?
    private var currentRequestTask: Task<Void, Never>?
    private var highlightAutoHideTask: Task<Void, Never>?
    private var highlightClickMonitorStartTask: Task<Void, Never>?
    private var highlightGlobalClickMonitor: Any?
    private var highlightLocalClickMonitor: Any?
    private var shouldRestoreAnswerWindowAfterHighlight = false
    private var windowsHiddenForHighlight: [NSWindow] = []
    private var shouldRelaunchAfterTerminate = false
    private var screenRecordingPrimerTask: Task<Void, Never>?
    private var shouldRestoreTranscriptAfterScreenRecordingPrompt = false
    private var shouldRestoreSettingsAfterScreenRecordingPrompt = false
    private var appActivationObserver: NSObjectProtocol?
    private var attentionRequestID: Int?
    private var isAwaitingAccessibilityGrant = false
    private var isUpdatePresentationActive = false
    private var standardWindowPresentationIDs = Set<String>()

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainService = KeychainService(),
        screenshotService: ScreenshotService = ScreenshotService(),
        openAIClient: OpenAIClient = OpenAIClient(),
        backendClient: BackendClient = BackendClient(),
        highlightGroundingService: HighlightGroundingService = HighlightGroundingService(),
        clipboardTextService: ClipboardTextService = ClipboardTextService(),
        selectionAutomationService: SelectionAutomationService = SelectionAutomationService(),
        safariPageCaptureService: SafariPageCaptureService = SafariPageCaptureService()
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.screenshotService = screenshotService
        self.openAIClient = openAIClient
        self.backendClient = backendClient
        self.highlightGroundingService = highlightGroundingService
        self.clipboardTextService = clipboardTextService
        self.selectionAutomationService = selectionAutomationService
        self.safariPageCaptureService = safariPageCaptureService
        self.answerWindowController = AnswerWindowController()
        self.settingsWindowController = SettingsWindowController()
        self.screenshotPreviewWindowController = ScreenshotPreviewWindowController()
        self.highlightOverlayController = HighlightOverlayController()
        self.cursorProgressOverlayController = CursorProgressOverlayController()
        let savedAccessMode = defaults.string(forKey: Self.accessModeKey)
        self.accessMode = AccessMode(rawValue: savedAccessMode ?? "") ?? .invite
        self.backendBaseURLInput = defaults.string(forKey: Self.backendBaseURLKey) ?? Self.defaultBackendBaseURL
        let savedModelID = defaults.string(forKey: Self.modelIDKey)
        let initialModelID: String
        if let savedModelID, !Self.retiredModelAliases.contains(savedModelID) {
            initialModelID = savedModelID
        } else {
            initialModelID = ModelPreset.gpt56HighFast.modelID
            defaults.set(ModelPreset.gpt56HighFast.modelID, forKey: Self.modelIDKey)
        }
        let initialReasoningEffort = defaults.string(forKey: Self.reasoningEffortKey) ?? ModelPreset.gpt56HighFast.reasoningEffort
        let initialServiceTier = defaults.string(forKey: Self.serviceTierKey) ?? ModelPreset.gpt56HighFast.serviceTier
        self.modelID = initialModelID
        self.reasoningEffort = initialReasoningEffort
        self.serviceTier = initialServiceTier
        self.imageDetail = defaults.string(forKey: Self.imageDetailKey) ?? ModelPreset.gpt56HighFast.imageDetail
        if defaults.object(forKey: Self.automaticallyIncludeSafariPageContentKey) == nil {
            self.automaticallyIncludeSafariPageContent = true
        } else {
            self.automaticallyIncludeSafariPageContent = defaults.bool(forKey: Self.automaticallyIncludeSafariPageContentKey)
        }
        self.translationLanguagePair = TranslationLanguagePair(
            rawValue: defaults.string(forKey: Self.translationLanguagePairKey) ?? ""
        ) ?? .automatic
        if defaults.object(forKey: Self.transcriptTextSizeKey) == nil {
            self.transcriptTextSize = Self.defaultTranscriptTextSize
        } else {
            self.transcriptTextSize = Self.clampedTranscriptTextSize(
                defaults.double(forKey: Self.transcriptTextSizeKey)
            )
        }
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
        let savedTranslateSelectionHotkeyKeyCode = UInt32(defaults.integer(forKey: Self.translateSelectionHotkeyKeyCodeKey))
        self.translateSelectionHotkeyKeyCode = savedTranslateSelectionHotkeyKeyCode == 0
            ? HotkeyConfiguration.defaultTranslateSelectionConfiguration.keyCode
            : savedTranslateSelectionHotkeyKeyCode
        let savedTranslateSelectionHotkeyModifiers = UInt32(defaults.integer(forKey: Self.translateSelectionHotkeyModifiersKey))
        self.translateSelectionHotkeyModifiers = savedTranslateSelectionHotkeyModifiers == 0
            ? HotkeyConfiguration.defaultTranslateSelectionConfiguration.modifiers
            : savedTranslateSelectionHotkeyModifiers
        self.hotkeyDescription = hotkeyConfiguration.displayName
        self.translateClipboardHotkeyDescription = translateClipboardHotkeyConfiguration.displayName
        self.translateSelectionHotkeyDescription = translateSelectionHotkeyConfiguration.displayName
        refreshStoredAPIKeyPreview()
        refreshStoredBackendAccessTokenPreview()
        if savedAccessMode == nil, !hasStoredBackendAccessToken, hasStoredAPIKey {
            accessMode = .apiKey
        }
        if defaults.object(forKey: Self.hasCompletedFirstLaunchOnboardingKey) == nil,
           defaults.bool(forKey: Self.hasCompletedFirstLaunchKey) {
            defaults.set(true, forKey: Self.hasCompletedFirstLaunchOnboardingKey)
        }
        applySelectedModelPreset()
    }

    func start() {
        DiagnosticLogger.log("AppModel start. screenRecording=\(CGPreflightScreenCaptureAccess()) accessMode=\(accessMode.rawValue) hasInviteToken=\(hasStoredBackendAccessToken) hasAPIKey=\(hasStoredAPIKey)", category: "Lifecycle")
        closeUnmanagedSettingsWindows()
        closeRestoredSettingsWindowsAfterLaunch()
        if hotkeyManager == nil {
            updateHotkeyRegistration()
        }
        if translateClipboardHotkeyManager == nil {
            updateTranslateClipboardHotkeyRegistration()
        }
        if translateSelectionHotkeyManager == nil {
            updateTranslateSelectionHotkeyRegistration()
        }

        registerAppActivationObserverIfNeeded()
        refreshAccessibilityPermissionState()
        refreshScreenRecordingPermissionState()
    }

    private func refreshScreenRecordingPermissionState() {
        if ScreenRecordingPermissionStore.markGrantConfirmedIfGranted() {
            shouldOfferPermissionRelaunch = false
        }
    }

    private func noteScreenRecordingRelaunchNeeded() {
        guard ScreenRecordingPermissionStore.needsRelaunchForGrantedAccess else { return }

        shouldOfferPermissionRelaunch = true
        statusMessage = "Screen Recording is enabled in System Settings, but Sasu needs one more relaunch before capture works."
    }

    private func refreshAccessibilityPermissionState() {
        hasAccessibilityAccess = selectionAutomationService.hasAccessibilityAccess()

        guard hasAccessibilityAccess else {
            if isAwaitingAccessibilityGrant {
                shouldOfferAccessibilityRelaunch = true
                statusMessage = "If you enabled Sasu in Accessibility settings, relaunch Sasu for Translate Selection to work."
            }
            return
        }

        isAwaitingAccessibilityGrant = false
        shouldOfferAccessibilityRelaunch = false
    }

    func showLaunchWindowIfNeeded() {
        let shouldRestoreSettings = defaults.bool(forKey: Self.shouldShowSettingsOnLaunchKey)
        defaults.set(true, forKey: Self.hasCompletedFirstLaunchKey)
        let shouldShowSettings = !hasConfiguredAccess || shouldRestoreSettings

        Task {
            await MainActor.run {
                closeUnmanagedSettingsWindows()
                NSApp.setActivationPolicy(.regular)
                if ScreenRecordingPermissionStore.markGrantConfirmedIfGranted() {
                    refreshScreenRecordingPermissionState()
                    isFirstLaunchOnboardingVisible = false
                    isOnboardingGuidanceVisible = false
                    if shouldShowSettings {
                        self.showSettingsWindowWithStandardOrdering()
                    } else {
                        answerWindowController.show(appModel: self)
                    }
                    return
                }

                if ScreenRecordingPermissionStore.needsRelaunchForGrantedAccess {
                    noteScreenRecordingRelaunchNeeded()
                }

                if shouldShowFirstLaunchOnboarding {
                    showFirstLaunchOnboarding()
                } else if shouldShowSettings {
                    self.showSettingsWindowWithStandardOrdering()
                } else {
                    answerWindowController.show(appModel: self)
                }

                if !shouldShowFirstLaunchOnboarding,
                   !ScreenRecordingPermissionStore.hasStartedSetup {
                    presentScreenRecordingPrimerIfNeeded()
                }
            }
        }
    }

    func showSettingsWindow() {
        showSettingsWindowWithStandardOrdering()
        defaults.set(true, forKey: Self.shouldShowSettingsOnLaunchKey)
    }

    func showWindowForReopen() {
        if isFirstLaunchOnboardingVisible || (!CGPreflightScreenCaptureAccess() && shouldShowFirstLaunchOnboarding) {
            showFirstLaunchOnboarding()
        } else if hasConfiguredAccess {
            answerWindowController.show(appModel: self)
        } else {
            showSettingsWindowWithStandardOrdering()
        }
    }

    func showTranscriptWindow() {
        answerWindowController.show(appModel: self)
    }

    private var shouldShowFirstLaunchOnboarding: Bool {
        !defaults.bool(forKey: Self.hasCompletedFirstLaunchOnboardingKey)
    }

    private func showFirstLaunchOnboarding() {
        DiagnosticLogger.log("Showing first launch onboarding.", category: "Onboarding")
        isFirstLaunchOnboardingVisible = true
        isOnboardingGuidanceVisible = false
        errorMessage = nil
        shouldOfferPermissionRelaunch = false
        statusMessage = "Welcome to Sasu. Try the example before enabling Screen Recording."
        answerWindowController.show(appModel: self)
    }

    func showOnboardingGuidance() {
        isOnboardingGuidanceVisible = true
        statusMessage = "Sasu can point to the next place to click."
    }

    func hideOnboardingGuidance() {
        isOnboardingGuidanceVisible = false
        statusMessage = "Welcome to Sasu. Try the example before enabling Screen Recording."
    }

    func completeFirstLaunchOnboarding() {
        DiagnosticLogger.log("First launch onboarding completed. screenRecording=\(CGPreflightScreenCaptureAccess())", category: "Onboarding")
        defaults.set(true, forKey: Self.hasCompletedFirstLaunchOnboardingKey)
        isFirstLaunchOnboardingVisible = false
        isOnboardingGuidanceVisible = false
        statusMessage = "Next, enable Screen Recording so Sasu can see the page you ask about."

        if ScreenRecordingPermissionStore.markGrantConfirmedIfGranted() {
            refreshScreenRecordingPermissionState()
            statusMessage = "Screen Recording permission granted. Press \(hotkeyDescription) or use Capture Screen."
            return
        }

        if ScreenRecordingPermissionStore.needsRelaunchForGrantedAccess {
            noteScreenRecordingRelaunchNeeded()
            return
        }

        presentScreenRecordingPrimerIfNeeded()
    }

    func contactDeveloperAboutOnboarding() {
        let email = "justin.garcia@gmail.com"
        let subject = "Question about Sasu"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject)
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    private var hasConfiguredAccess: Bool {
        switch accessMode {
        case .invite:
            return hasStoredBackendAccessToken
        case .apiKey:
            return hasStoredAPIKey
        }
    }

    func beginAboutWindowPresentation() {
        beginStandardWindowPresentation(Self.aboutWindowPresentationID)
    }

    func endAboutWindowPresentation() {
        endStandardWindowPresentation(Self.aboutWindowPresentationID)
    }

    func prepareForUpdatePresentation() {
        DiagnosticLogger.log("Preparing for update presentation.", category: "Updater")
        beginUpdatePresentation()
    }

    func beginUpdatePresentation() {
        isUpdatePresentationActive = true
        applyAnswerWindowFloatingPolicy()
    }

    func endUpdatePresentation() {
        isUpdatePresentationActive = false
        applyAnswerWindowFloatingPolicy()
    }

    private func showSettingsWindowWithStandardOrdering() {
        beginStandardWindowPresentation(Self.settingsWindowPresentationID)
        settingsWindowController.show(appModel: self) { [weak self] in
            self?.endStandardWindowPresentation(Self.settingsWindowPresentationID)
        }
        closeUnmanagedSettingsWindows()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            closeUnmanagedSettingsWindows()
        }
    }

    private func beginStandardWindowPresentation(_ identifier: String) {
        standardWindowPresentationIDs.insert(identifier)
        applyAnswerWindowFloatingPolicy()
    }

    private func endStandardWindowPresentation(_ identifier: String) {
        standardWindowPresentationIDs.remove(identifier)
        applyAnswerWindowFloatingPolicy()
    }

    private func applyAnswerWindowFloatingPolicy() {
        let shouldFloat = standardWindowPresentationIDs.isEmpty && !isUpdatePresentationActive
        answerWindowController.setFloatingEnabled(shouldFloat)
    }

    func closeUnmanagedSettingsWindows() {
        NSApp.windows
            .filter { window in
                window.title == "Sasu Settings" && !settingsWindowController.owns(window)
            }
            .forEach { window in
                window.close()
            }
    }

    private func closeRestoredSettingsWindowsAfterLaunch() {
        Task { @MainActor in
            for delay in [100_000_000, 500_000_000, 1_500_000_000] {
                try? await Task.sleep(nanoseconds: UInt64(delay))
                closeUnmanagedSettingsWindows()
            }
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

    func redeemInviteCodeFromInput() {
        redeemInviteCode(inviteCodeInput)
    }

    func deleteBackendAccessToken() {
        do {
            try keychain.deleteBackendAccessToken()
            hasStoredBackendAccessToken = false
            backendAccessTokenPreview = ""
            backendAccessLabel = ""
            defaults.removeObject(forKey: Self.backendAccessLabelKey)
            errorMessage = nil
            statusMessage = "Sasu backend access cleared."
        } catch {
            errorMessage = "Could not clear Sasu backend access: \(error.localizedDescription)"
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

    private func refreshStoredBackendAccessTokenPreview() {
        backendAccessLabel = defaults.string(forKey: Self.backendAccessLabelKey) ?? ""
        guard let token = try? keychain.readBackendAccessToken(), !token.isEmpty else {
            hasStoredBackendAccessToken = false
            backendAccessTokenPreview = ""
            return
        }

        hasStoredBackendAccessToken = true
        backendAccessTokenPreview = Self.backendTokenPreview(for: token)
    }

    private static func backendTokenPreview(for token: String) -> String {
        "sasu_app_...\(token.suffix(4))"
    }

    func handleOpenedURL(_ url: URL) {
        if let inviteCode = Self.inviteCode(from: url) {
            inviteCodeInput = inviteCode
            accessMode = .invite
            showSettingsWindowWithStandardOrdering()
            redeemInviteCode(inviteCode)
            return
        }

        errorMessage = "Sasu could not read this link."
        showSettingsWindowWithStandardOrdering()
    }

    private func redeemInviteCode(_ rawCode: String) {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            errorMessage = "Paste an invite code before redeeming."
            return
        }
        guard let backendBaseURL else {
            errorMessage = AppError.invalidBackendURL.localizedDescription
            return
        }

        isRequestInFlight = true
        errorMessage = nil
        statusMessage = "Redeeming invite..."

        Task { @MainActor in
            do {
                let redemption = try await backendClient.redeemInvite(
                    code: code,
                    backendBaseURL: backendBaseURL
                )
                try keychain.saveBackendAccessToken(redemption.accessToken)
                defaults.set(redemption.label, forKey: Self.backendAccessLabelKey)
                inviteCodeInput = ""
                accessMode = .invite
                backendAccessLabel = redemption.label
                backendAccessTokenPreview = Self.backendTokenPreview(for: redemption.accessToken)
                hasStoredBackendAccessToken = true
                errorMessage = nil
                statusMessage = "Invite accepted. Sasu is ready."
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = "Could not redeem invite."
            }

            isRequestInFlight = false
        }
    }

    private var backendBaseURL: URL? {
        let trimmedURL = backendBaseURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil else {
            return nil
        }
        return url
    }

    private static func inviteCode(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "sasu", url.host?.lowercased() == "invite" else {
            return nil
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first { $0.name == "code" }?.value
    }

    private func requestCredential() throws -> AIRequestCredential {
        switch accessMode {
        case .invite:
            guard let token = try keychain.readBackendAccessToken(), !token.isEmpty else {
                throw AppError.missingInviteAccess
            }
            guard let backendBaseURL else {
                throw AppError.invalidBackendURL
            }
            return .backendAccessToken(token, baseURL: backendBaseURL)
        case .apiKey:
            guard let apiKey = try keychain.readAPIKey(), !apiKey.isEmpty else {
                throw AppError.missingAPIKey
            }
            return .openAIAPIKey(apiKey)
        }
    }

    func resetModelToDefault() {
        selectedModelPresetID = ModelPreset.gpt56HighFast.id
        applySelectedModelPreset()
        errorMessage = nil
        statusMessage = "Model reset to \(ModelPreset.gpt56HighFast.label)."
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
        switch presetID {
        case "gpt55High", "gpt55HighFast":
            return ModelPreset.gpt56HighFast.id
        case "gpt55MediumFast":
            return ModelPreset.gpt56MediumFast.id
        default:
            return ModelPreset.all.contains { $0.id == presetID } ? presetID : nil
        }
    }

    private static func clampedTranscriptTextSize(_ size: Double) -> Double {
        min(max(size, minimumTranscriptTextSize), maximumTranscriptTextSize)
    }

    var canIncreaseTranscriptTextSize: Bool {
        transcriptTextSize < Self.maximumTranscriptTextSize
    }

    var canDecreaseTranscriptTextSize: Bool {
        transcriptTextSize > Self.minimumTranscriptTextSize
    }

    func increaseTranscriptTextSize() {
        transcriptTextSize += Self.transcriptTextSizeStep
    }

    func decreaseTranscriptTextSize() {
        transcriptTextSize -= Self.transcriptTextSizeStep
    }

    func resetTranscriptTextSize() {
        transcriptTextSize = Self.defaultTranscriptTextSize
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

    func setTranslateSelectionHotkeyModifier(_ modifier: UInt32, enabled: Bool) {
        if enabled {
            translateSelectionHotkeyModifiers |= modifier
        } else {
            let updatedModifiers = translateSelectionHotkeyModifiers & ~modifier
            guard updatedModifiers != 0 else {
                errorMessage = "Choose at least one modifier for the Translate Selection hotkey."
                return
            }

            translateSelectionHotkeyModifiers = updatedModifiers
        }
    }

    func resetTranslateSelectionHotkeyToDefault() {
        translateSelectionHotkeyKeyCode = HotkeyConfiguration.defaultTranslateSelectionConfiguration.keyCode
        translateSelectionHotkeyModifiers = HotkeyConfiguration.defaultTranslateSelectionConfiguration.modifiers
        statusMessage = "Translate Selection hotkey reset to \(translateSelectionHotkeyDescription)."
    }

    func captureAndAsk() {
        guard !isRequestInFlight else { return }
        guard !isFirstLaunchOnboardingVisible else {
            statusMessage = "Click Sasuを始める in the example to enable Screen Recording first."
            return
        }

        currentRequestTask = Task {
            await prepareScreenshotForQuery()
        }
    }

    func translateClipboard() {
        guard !isRequestInFlight else { return }
        guard !isFirstLaunchOnboardingVisible else {
            statusMessage = "Click Sasuを始める in the example to enable Screen Recording first."
            return
        }

        currentRequestTask = Task {
            await runTranslateClipboard()
        }
    }

    func translateSelection() {
        guard !isRequestInFlight else { return }
        guard !isFirstLaunchOnboardingVisible else {
            statusMessage = "Click Sasuを始める in the example to enable Screen Recording first."
            return
        }

        currentRequestTask = Task {
            await runTranslateSelection()
        }
    }

    func sendFollowUp() {
        guard !isFirstLaunchOnboardingVisible else {
            statusMessage = "Click Sasuを始める in the example to enable Screen Recording first."
            return
        }
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

        beginStandardWindowPresentation(Self.screenshotPreviewWindowPresentationID)
        screenshotPreviewWindowController.show(image: image) { [weak self] in
            guard let self else { return }
            endStandardWindowPresentation(Self.screenshotPreviewWindowPresentationID)
            answerWindowController.show(appModel: self, activate: true)
        }
    }

    func showHighlight(_ highlightSuggestion: HighlightSuggestion? = nil) {
        guard let highlight = highlightSuggestion ?? currentHighlightSuggestion, let lastScreenshot else { return }
        currentHighlightSuggestion = highlight
        highlightAutoHideTask?.cancel()
        highlightClickMonitorStartTask?.cancel()
        stopHighlightClickMonitoring()
        shouldRestoreAnswerWindowAfterHighlight = true
        highlightClickMonitorStartTask = Task { [weak self, highlight, lastScreenshot] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.windowsHiddenForHighlight = Self.hideVisibleSasuWindowsForCapture()
                self.highlightOverlayController.show(
                    highlight: highlight,
                    screenshot: lastScreenshot
                )
                self.isHighlightVisible = true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.isHighlightVisible == true else { return }
                self?.startHighlightClickMonitoring()
            }
        }
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
        highlightClickMonitorStartTask?.cancel()
        highlightClickMonitorStartTask = nil
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
                self?.closeUnmanagedSettingsWindows()
                self?.restoreHighlightWindowsAfterUserReturn()
                self?.restoreWindowsAfterScreenRecordingPermissionIfNeeded()
                self?.refreshAccessibilityPermissionState()
                self?.refreshScreenRecordingPermissionState()
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
        ScreenRecordingPermissionStore.markSetupStarted()
        shouldOfferPermissionRelaunch = false

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

    func openAccessibilitySettings() {
        isAwaitingAccessibilityGrant = true
        shouldOfferAccessibilityRelaunch = false

        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")
        ].compactMap { $0 }

        statusMessage = "Opened Accessibility settings. Enable Sasu, then relaunch Sasu."

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

        errorMessage = "Open System Settings > Privacy & Security > Accessibility, then enable Sasu."
    }

    func openAutomationSettings() {
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"),
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")
        ].compactMap { $0 }

        statusMessage = "Opened Automation settings. Enable Safari under Sasu, then capture Safari again."

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

        errorMessage = "Open System Settings > Privacy & Security > Automation, then enable Safari under Sasu."
    }

    func requestAccessibilityAccess() {
        isAwaitingAccessibilityGrant = true
        shouldOfferAccessibilityRelaunch = false
        selectionAutomationService.requestAccessibilityAccess()
        statusMessage = "Approve the macOS Accessibility prompt, or enable Sasu in System Settings, then relaunch Sasu."
        refreshAccessibilityPermissionState()
    }

    private func presentScreenRecordingPrimerIfNeeded() {
        if ScreenRecordingPermissionStore.markGrantConfirmedIfGranted() {
            refreshScreenRecordingPermissionState()
            return
        }

        if ScreenRecordingPermissionStore.hasStartedSetup {
            noteScreenRecordingRelaunchNeeded()
            return
        }

        DiagnosticLogger.log("Presenting Screen Recording primer.", category: "Permissions")

        screenRecordingPrimerTask?.cancel()
        screenRecordingPrimerTask = Task { @MainActor in
            // Let the Settings window finish appearing before presenting the modal primer.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            if ScreenRecordingPermissionStore.markGrantConfirmedIfGranted() {
                refreshScreenRecordingPermissionState()
                return
            }

            if ScreenRecordingPermissionStore.needsRelaunchForGrantedAccess {
                noteScreenRecordingRelaunchNeeded()
                return
            }

            noteWindowsToRestoreAfterScreenRecordingPrompt()
            hideWindowsForSystemPermissionPrompt()
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Sasu Needs Screen Recording"
            alert.informativeText = """
            Sasu captures your screen only when you press the hotkey or Capture Screen, then sends that screenshot to OpenAI with your question.

            macOS requires Screen Recording permission before Sasu can see the page or app you want help with.
            """
            alert.addButton(withTitle: "Accept Screen Recording")
            alert.addButton(withTitle: "Not Yet")

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                DiagnosticLogger.log("User chose Accept Screen Recording.", category: "Permissions")
                requestScreenRecordingPermission()
            default:
                DiagnosticLogger.log("User chose Not Yet for Screen Recording.", category: "Permissions")
                showFirstLaunchOnboarding()
            }

            screenRecordingPrimerTask = nil
        }
    }

    private func requestScreenRecordingPermission() {
        DiagnosticLogger.log("Requesting Screen Recording permission.", category: "Permissions")

        if ScreenRecordingPermissionStore.markGrantConfirmedIfGranted() {
            refreshScreenRecordingPermissionState()
            statusMessage = "Screen Recording permission granted. Press \(hotkeyDescription) or use Capture Screen."
            restoreWindowsAfterScreenRecordingPrompt()
            return
        }

        if ScreenRecordingPermissionStore.hasStartedSetup {
            noteScreenRecordingRelaunchNeeded()
            restoreWindowsAfterScreenRecordingPrompt()
            return
        }

        ScreenRecordingPermissionStore.markAccessRequested()
        noteWindowsToRestoreAfterScreenRecordingPrompt()
        hideWindowsForSystemPermissionPrompt()

        statusMessage = "Waiting for Screen Recording permission..."
        _ = CGRequestScreenCaptureAccess()

        if ScreenRecordingPermissionStore.markGrantConfirmedIfGranted() {
            DiagnosticLogger.log("Screen Recording permission granted immediately.", category: "Permissions")
            refreshScreenRecordingPermissionState()
            statusMessage = "Screen Recording permission granted. Press \(hotkeyDescription) or use Capture Screen."
            restoreWindowsAfterScreenRecordingPrompt()
        } else {
            DiagnosticLogger.log("Screen Recording permission not granted after request.", category: "Permissions")
            statusMessage = "Approve the macOS Screen Recording prompt. If you do not see it, use Open Screen Recording Settings."
        }
    }

    private func noteWindowsToRestoreAfterScreenRecordingPrompt() {
        if hasConfiguredAccess {
            shouldRestoreTranscriptAfterScreenRecordingPrompt = true
            shouldRestoreSettingsAfterScreenRecordingPrompt = false
        } else {
            shouldRestoreSettingsAfterScreenRecordingPrompt = true
            shouldRestoreTranscriptAfterScreenRecordingPrompt = false
        }
    }

    private func hideWindowsForSystemPermissionPrompt() {
        answerWindowController.hide()
        settingsWindowController.hide()
    }

    private func restoreWindowsAfterScreenRecordingPermissionIfNeeded() {
        guard shouldRestoreTranscriptAfterScreenRecordingPrompt
            || shouldRestoreSettingsAfterScreenRecordingPrompt
        else { return }

        if ScreenRecordingPermissionStore.markGrantConfirmedIfGranted() {
            refreshScreenRecordingPermissionState()
            statusMessage = "Screen Recording permission granted. Press \(hotkeyDescription) or use Capture Screen."
        }

        restoreWindowsAfterScreenRecordingPrompt()
    }

    private func restoreWindowsAfterScreenRecordingPrompt() {
        if shouldRestoreSettingsAfterScreenRecordingPrompt {
            showSettingsWindowWithStandardOrdering()
        } else if shouldRestoreTranscriptAfterScreenRecordingPrompt {
            answerWindowController.show(appModel: self)
        }

        shouldRestoreTranscriptAfterScreenRecordingPrompt = false
        shouldRestoreSettingsAfterScreenRecordingPrompt = false
    }

    func relaunchSasu() {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            errorMessage = "Quit this process and launch Sasu from Build/Sasu.app so macOS applies permission changes to the app bundle."
            return
        }

        shouldRelaunchAfterTerminate = true
        NSApp.terminate(nil)
    }

    func performRelaunchIfNeeded() {
        guard shouldRelaunchAfterTerminate else { return }

        shouldRelaunchAfterTerminate = false
        let bundleURL = Bundle.main.bundleURL
        NSWorkspace.shared.open(bundleURL)
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

    private var translateSelectionHotkeyConfiguration: HotkeyConfiguration {
        HotkeyConfiguration(
            keyCode: translateSelectionHotkeyKeyCode,
            modifiers: translateSelectionHotkeyModifiers
        )
    }

    private var hotkeyReadinessMessage: String {
        "Ready. Press \(hotkeyDescription) to capture, \(translateClipboardHotkeyDescription) to translate clipboard, or \(translateSelectionHotkeyDescription) to translate selection."
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
            statusMessage = hotkeyReadinessMessage
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
            statusMessage = hotkeyReadinessMessage
        } catch {
            errorMessage = "Could not register \(translateClipboardHotkeyDescription): \(error.localizedDescription)"
            statusMessage = "Use Translate Clipboard from the app while the hotkey is unavailable."
        }
    }

    private func updateTranslateSelectionHotkeyRegistration() {
        translateSelectionHotkeyManager?.unregister()
        translateSelectionHotkeyManager = nil

        translateSelectionHotkeyDescription = translateSelectionHotkeyConfiguration.displayName
        let manager = HotkeyManager(configuration: translateSelectionHotkeyConfiguration, identifier: 3) { [weak self] in
            Task { @MainActor in
                self?.translateSelection()
            }
        }

        do {
            try manager.register()
            translateSelectionHotkeyManager = manager
            errorMessage = nil
            statusMessage = hotkeyReadinessMessage
        } catch {
            errorMessage = "Could not register \(translateSelectionHotkeyDescription): \(error.localizedDescription)"
            statusMessage = "Use Translate Selection from the app while the hotkey is unavailable."
        }
    }

    private func prepareScreenshotForQuery() async {
        isRequestInFlight = true
        errorMessage = nil
        shouldOfferPermissionRelaunch = false
        statusMessage = "Capturing screen..."
        Self.logger.info("Preparing screenshot for user query.")

        do {
            try Task.checkCancellation()
            let capturedScreenshot = try await captureMainDisplayWithSasuWindowsHidden()
            let screenshot = await screenshotIncludingSafariPageContextIfNeeded(capturedScreenshot)
            let isFirstScreenshot = transcriptMessages.isEmpty
            lastScreenshot = screenshot
            screenshotPreviewImage = NSImage(data: screenshot.pngData)
            isScreenshotPrepared = true
            appendScreenshotMessage(for: screenshot)
            followUpText = isFirstScreenshot
                ? (screenshot.browserPageContext == nil ? "Explain this" : "Explain this page")
                : "What now?"
            querySelectionNonce += 1
            currentHighlightSuggestion = nil
            hideHighlight()
            if let browserPageContext = screenshot.browserPageContext {
                statusMessage = "Screenshot and Safari page ready. Type your question and press Send."
                Self.logger.info("Prepared screenshot with Safari page. bytes=\(screenshot.pngData.count), pixelWidth=\(Int(screenshot.pixelSize.width)), pixelHeight=\(Int(screenshot.pixelSize.height)), pageCharacters=\(browserPageContext.text.count)")
            } else if screenshot.browserPageCaptureIssue != nil {
                statusMessage = "Screenshot ready, but Safari page content was not included."
                Self.logger.info("Prepared screenshot without Safari page after attempted Safari capture. bytes=\(screenshot.pngData.count), pixelWidth=\(Int(screenshot.pixelSize.width)), pixelHeight=\(Int(screenshot.pixelSize.height))")
            } else {
                statusMessage = "Screenshot ready. Type your question and press Send."
                Self.logger.info("Prepared screenshot. bytes=\(screenshot.pngData.count), pixelWidth=\(Int(screenshot.pixelSize.width)), pixelHeight=\(Int(screenshot.pixelSize.height))")
            }
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
            let sourceReadings = JapaneseReadingService.readings(for: sourceText)
            let readingCount = sourceReadings?.filter { $0.reading?.isEmpty == false }.count ?? 0
            DiagnosticLogger.log(
                "Generated local clipboard readings. sourceCharacters=\(sourceText.count) readingSegments=\(sourceReadings?.count ?? 0) segmentsWithReadings=\(readingCount)",
                category: "Readings"
            )
            let sourceMessage = ChatTranscriptMessage(
                role: .user,
                text: "Clipboard text: \(sourceText)",
                sourceReadings: sourceReadings
            )
            transcriptMessages.append(sourceMessage)

            try Task.checkCancellation()
            let credential = try requestCredential()

            statusMessage = "Translating clipboard..."
            answerWindowController.show(appModel: self)
            let result = try await openAIClient.translateClipboardText(
                credential: credential,
                modelID: modelID,
                reasoningEffort: reasoningEffort,
                serviceTier: serviceTier,
                sourceText: sourceText,
                translationDirection: TranslationDirection.forUserInterface(
                    languagePair: translationLanguagePair
                ),
                conversationContext: conversationContext
            )
            try Task.checkCancellation()
            let translation = "Translation: \(Self.normalizedTranslationText(result))"

            lastResponse = AssistantResponse(
                text: translation,
                prompt: "Translate clipboard",
                actionSuggestion: nil
            )
            transcriptMessages.append(ChatTranscriptMessage(role: .assistant, text: translation))
            statusMessage = "Clipboard translation ready."
            DiagnosticLogger.log("Clipboard translation ready. sourceCharacters=\(sourceText.count) localSegmentsWithReadings=\(readingCount)", category: "OpenAI")
            Self.logger.info("Clipboard translation ready. sourceCharacters=\(sourceText.count), answerCharacters=\(translation.count), localSegmentsWithReadings=\(readingCount)")
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

    private func runTranslateSelection() async {
        isRequestInFlight = true
        cursorProgressOverlayController.show()
        defer {
            cursorProgressOverlayController.hide()
        }

        errorMessage = nil
        shouldOfferPermissionRelaunch = false
        statusMessage = "Translating selection..."
        Self.logger.info("Starting selection translation flow. model=\(self.modelID, privacy: .public), reasoning=\(self.reasoningEffort, privacy: .public), serviceTier=\(self.serviceTier, privacy: .public)")

        var pasteboardBackup: PasteboardBackup?

        do {
            try Task.checkCancellation()

            guard selectionAutomationService.hasAccessibilityAccess() else {
                isAwaitingAccessibilityGrant = true
                shouldOfferAccessibilityRelaunch = true
                selectionAutomationService.requestAccessibilityAccess()
                throw SelectionAutomationError.accessibilityRequired
            }

            let copiedSelection = try await selectionAutomationService.copySelectedText()
            pasteboardBackup = copiedSelection.backup
            let sourceText = copiedSelection.text

            try Task.checkCancellation()
            let credential = try requestCredential()

            let answer = try await openAIClient.translateClipboardText(
                credential: credential,
                modelID: modelID,
                reasoningEffort: reasoningEffort,
                serviceTier: serviceTier,
                sourceText: sourceText,
                translationDirection: TranslationDirection.forUserInterface(
                    languagePair: translationLanguagePair
                ),
                conversationContext: nil,
                forSelectionReplacement: true
            )
            try Task.checkCancellation()

            let translation = Self.normalizedTranslationText(answer)

            try await selectionAutomationService.pasteTranslation(
                translation,
                restoring: copiedSelection.backup
            )
            pasteboardBackup = nil

            statusMessage = "Selection translated."
            Self.logger.info("Selection translation ready. sourceCharacters=\(sourceText.count), answerCharacters=\(translation.count)")
        } catch is CancellationError {
            if let pasteboardBackup {
                pasteboardBackup.restore()
            }
            statusMessage = "Request stopped."
            errorMessage = nil
            Self.logger.info("Selection translation cancelled.")
        } catch {
            if let pasteboardBackup {
                pasteboardBackup.restore()
            }
            errorMessage = error.localizedDescription
            statusMessage = "Selection translation failed."
            Self.logger.error("Selection translation failed: \(error.localizedDescription, privacy: .public)")
            requestUserAttentionIfNeeded()
        }

        isRequestInFlight = false
        currentRequestTask = nil
    }

    private static func normalizedTranslationText(_ text: String) -> String {
        normalizedAnswerText(text)
    }

    private static func normalizedAnswerText(_ text: String) -> String {
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
            let credential = try requestCredential()

            var screenshot: ScreenshotPayload
            if reuseLastScreenshot, let existingScreenshot = lastScreenshot {
                screenshot = existingScreenshot
            } else {
                try Task.checkCancellation()
                let capturedScreenshot = try await captureMainDisplayWithSasuWindowsHidden()
                screenshot = await screenshotIncludingSafariPageContextIfNeeded(capturedScreenshot)
                lastScreenshot = screenshot
                screenshotPreviewImage = NSImage(data: screenshot.pngData)
                isScreenshotPrepared = true
                appendScreenshotMessage(for: screenshot)
            }
            try Task.checkCancellation()
            screenshot = confirmLargeSafariPageContextBeforeSending(screenshot)
            try Task.checkCancellation()
            Self.logger.info("Screenshot ready. bytes=\(screenshot.pngData.count), pixelWidth=\(Int(screenshot.pixelSize.width)), pixelHeight=\(Int(screenshot.pixelSize.height))")

            statusMessage = "Asking OpenAI..."
            answerWindowController.show(appModel: self)
            let result = try await openAIClient.askAboutScreenshot(
                credential: credential,
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
            let answer = Self.normalizedAnswerText(result.answer)

            lastResponse = AssistantResponse(
                text: answer,
                prompt: prompt,
                actionSuggestion: actionSuggestion
            )
            currentHighlightSuggestion = actionSuggestion
            hideHighlight()
            transcriptMessages.append(
                ChatTranscriptMessage(
                    role: .assistant,
                    text: answer,
                    actionSuggestion: actionSuggestion
                )
            )
            statusMessage = "Answer ready."
            Self.logger.info("OpenAI answer ready. characters=\(answer.count), hasHighlight=\(actionSuggestion != nil)")
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
        let screenshotDescription = "\(Int(screenshot.pixelSize.width)) x \(Int(screenshot.pixelSize.height))"

        transcriptMessages.append(
            ChatTranscriptMessage(
                role: .screenshot,
                text: screenshotDescription,
                imageData: screenshot.pngData,
                browserPageContext: screenshot.browserPageContext,
                browserPageCaptureIssue: screenshot.browserPageCaptureIssue
            )
        )
    }

    private func confirmLargeSafariPageContextBeforeSending(_ screenshot: ScreenshotPayload) -> ScreenshotPayload {
        guard let pageContext = screenshot.browserPageContext,
              pageContext.text.count > Self.safariPageSendConfirmationCharacterThreshold else {
            return screenshot
        }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Include Full Safari Page?"
        alert.informativeText = """
        This page contains \(pageContext.text.count) characters. Including it may make the response slower.

        Do you want to include it?
        """
        alert.addButton(withTitle: "Include")
        alert.addButton(withTitle: "Do Not Include")

        if alert.runModal() == .alertFirstButtonReturn {
            DiagnosticLogger.log(
                "User included large Safari page context. characters=\(pageContext.text.count)",
                category: "Safari"
            )
            return screenshot
        }

        let reason = "You chose not to include the \(pageContext.text.count)-character Safari page context."
        let screenshotWithoutPageContext = screenshot.removingBrowserPageContext(reason: reason)
        lastScreenshot = screenshotWithoutPageContext
        replaceLatestScreenshotMessage(with: screenshotWithoutPageContext)
        DiagnosticLogger.log(
            "User excluded large Safari page context. characters=\(pageContext.text.count)",
            category: "Safari"
        )
        return screenshotWithoutPageContext
    }

    private func replaceLatestScreenshotMessage(with screenshot: ScreenshotPayload) {
        guard let index = transcriptMessages.lastIndex(where: { $0.role == .screenshot }) else { return }

        let existingMessage = transcriptMessages[index]
        transcriptMessages[index] = ChatTranscriptMessage(
            id: existingMessage.id,
            role: existingMessage.role,
            text: existingMessage.text,
            imageData: existingMessage.imageData,
            browserPageContext: screenshot.browserPageContext,
            browserPageCaptureIssue: screenshot.browserPageCaptureIssue,
            sourceReadings: existingMessage.sourceReadings,
            actionSuggestion: existingMessage.actionSuggestion
        )
    }

    private func captureMainDisplayWithSasuWindowsHidden() async throws -> ScreenshotPayload {
        let hiddenWindows = Self.hideVisibleSasuWindowsForCapture()
        if !hiddenWindows.isEmpty {
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        try Task.checkCancellation()
        defer {
            Self.restoreWindows(hiddenWindows)
        }

        return try await screenshotService.captureMainDisplay()
    }

    private func screenshotIncludingSafariPageContextIfNeeded(_ screenshot: ScreenshotPayload) async -> ScreenshotPayload {
        guard automaticallyIncludeSafariPageContent else { return screenshot }
        guard screenshot.frontmostApplicationBundleIdentifier == SafariPageCaptureService.safariBundleIdentifier else {
            DiagnosticLogger.log("Safari page capture skipped. foregroundBundle=\(screenshot.frontmostApplicationBundleIdentifier ?? "unknown") hasVisibleSafariWindow=\(screenshot.hasVisibleSafariWindow)", category: "Safari")
            return screenshot
        }

        if !defaults.bool(forKey: Self.hasAnsweredSafariPageCapturePrimerKey) {
            guard presentSafariPageCapturePrimer() else { return screenshot }
        }

        statusMessage = "Reading Safari page..."
        do {
            try Task.checkCancellation()
            DiagnosticLogger.log("Attempting Safari page capture. foregroundBundle=\(screenshot.frontmostApplicationBundleIdentifier ?? "unknown") hasVisibleSafariWindow=\(screenshot.hasVisibleSafariWindow)", category: "Safari")
            let pageContext = try safariPageCaptureService.captureCurrentPage()
            try Task.checkCancellation()
            errorMessage = nil
            DiagnosticLogger.log("Safari page capture ready. title=\(pageContext.displayTitle) characters=\(pageContext.text.count)", category: "Safari")
            return screenshot.addingBrowserPageContext(pageContext)
        } catch is CancellationError {
            return screenshot
        } catch {
            let issue = error.localizedDescription
            errorMessage = issue
            statusMessage = "Screenshot ready, but Safari page content was not included."
            Self.logger.error("Safari page capture failed: \(issue, privacy: .public)")
            DiagnosticLogger.log("Safari page capture failed: \(issue)", category: "Safari")
            return screenshot.addingBrowserPageCaptureIssue(issue)
        }
    }

    private func presentSafariPageCapturePrimer() -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Safari Enhancement"
        alert.informativeText = """
        Sasu can give guidance based on the full Safari page, not just what’s visible.

        When you capture Safari, Sasu can include the active tab title, URL, and page text with your screenshot. It only reads Safari page content when you capture, and sends it with your question.

        macOS may ask whether Sasu can control Safari. Safari may also require Safari > Develop > Developer Settings > Allow JavaScript from Apple Events.
        """
        alert.addButton(withTitle: "Enable for Safari")
        alert.addButton(withTitle: "Not Now")

        defaults.set(true, forKey: Self.hasAnsweredSafariPageCapturePrimerKey)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            DiagnosticLogger.log("User enabled Safari page capture.", category: "Permissions")
            return true
        default:
            DiagnosticLogger.log("User declined Safari page capture.", category: "Permissions")
            automaticallyIncludeSafariPageContent = false
            statusMessage = "Safari page capture is off. You can turn it on in Settings."
            return false
        }
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
    case missingInviteAccess
    case invalidBackendURL

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your OpenAI API key in Sasu before capturing the screen."
        case .missingInviteAccess:
            return "Open your Sasu invite link or redeem an invite code in Settings before using invite access."
        case .invalidBackendURL:
            return "Enter a valid Sasu backend URL in Settings."
        }
    }
}

enum AccessMode: String, CaseIterable, Identifiable {
    case invite
    case apiKey

    var id: String { rawValue }

    var label: String {
        switch self {
        case .invite:
            return "Invite access"
        case .apiKey:
            return "My OpenAI API key"
        }
    }
}
