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
    @Published var translationSourceLanguage: TranslationSourceLanguage {
        didSet { defaults.set(translationSourceLanguage.rawValue, forKey: Self.translationSourceLanguageKey) }
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
    @Published var captureAndAskHotkeyKeyCode: UInt32 {
        didSet {
            defaults.set(Int(captureAndAskHotkeyKeyCode), forKey: Self.captureAndAskHotkeyKeyCodeKey)
            updateCaptureAndAskHotkeyRegistration()
        }
    }
    @Published var captureAndAskHotkeyModifiers: UInt32 {
        didSet {
            defaults.set(Int(captureAndAskHotkeyModifiers), forKey: Self.captureAndAskHotkeyModifiersKey)
            updateCaptureAndAskHotkeyRegistration()
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
    @Published var translateAndReplaceHotkeyKeyCode: UInt32 {
        didSet {
            defaults.set(Int(translateAndReplaceHotkeyKeyCode), forKey: Self.translateAndReplaceHotkeyKeyCodeKey)
            updateTranslateAndReplaceHotkeyRegistration()
        }
    }
    @Published var translateAndReplaceHotkeyModifiers: UInt32 {
        didSet {
            defaults.set(Int(translateAndReplaceHotkeyModifiers), forKey: Self.translateAndReplaceHotkeyModifiersKey)
            updateTranslateAndReplaceHotkeyRegistration()
        }
    }
    @Published private(set) var hotkeyDescription = HotkeyConfiguration.defaultConfiguration.displayName
    @Published private(set) var captureAndAskHotkeyDescription = HotkeyConfiguration.defaultCaptureAndAskConfiguration.displayName
    @Published private(set) var translateSelectionHotkeyDescription = HotkeyConfiguration.defaultTranslateSelectionConfiguration.displayName
    @Published private(set) var translateAndReplaceHotkeyDescription = HotkeyConfiguration.defaultTranslateAndReplaceConfiguration.displayName
    @Published private(set) var statusMessage = String(localized: "Set up invite access or add your OpenAI API key, then use the Sasu command wheel.")
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
    @Published private(set) var streamingResponseText = ""
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
    private static let translationSourceLanguageKey = "translationSourceLanguage"
    private static let transcriptTextSizeKey = "transcriptTextSize"
    private static let hasAnsweredSafariPageCapturePrimerKey = "hasAnsweredSafariPageCapturePrimer"
    private static let safariPageSendConfirmationCharacterThreshold = 8_000
    private static let selectedModelPresetIDKey = "selectedModelPresetID"
    private static let hotkeyKeyCodeKey = "hotkeyKeyCode"
    private static let hotkeyModifiersKey = "hotkeyModifiers"
    private static let captureAndAskHotkeyKeyCodeKey = "captureAndAskHotkeyKeyCode"
    private static let captureAndAskHotkeyModifiersKey = "captureAndAskHotkeyModifiers"
    private static let translateSelectionHotkeyKeyCodeKey = "translateSelectionHotkeyKeyCode"
    private static let translateSelectionHotkeyModifiersKey = "translateSelectionHotkeyModifiers"
    private static let translateAndReplaceHotkeyKeyCodeKey = "translateAndReplaceHotkeyKeyCode"
    private static let translateAndReplaceHotkeyModifiersKey = "translateAndReplaceHotkeyModifiers"
    private static let hasAcknowledgedTranslateAndReplaceAccessibilityPrimerKey =
        "hasAcknowledgedTranslateAndReplaceAccessibilityPrimer"
    private static let hasAnsweredTranslateSelectionAccessibilityPrimerKey =
        "hasAnsweredTranslateSelectionAccessibilityPrimer"
    private static let suppressTranslateSelectionAccessibilityPrimerKey =
        "suppressTranslateSelectionAccessibilityPrimer"
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
    private let commandWheelController: CommandWheelController
    private var hotkeyManager: HotkeyManager?
    private var captureAndAskHotkeyManager: HotkeyManager?
    private var translateSelectionHotkeyManager: HotkeyManager?
    private var translateAndReplaceHotkeyManager: HotkeyManager?
    private var lastScreenshot: ScreenshotPayload?
    private var currentRequestTask: Task<Void, Never>?
    private var highlightAutoHideTask: Task<Void, Never>?
    private var highlightClickMonitorStartTask: Task<Void, Never>?
    private var highlightGlobalClickMonitor: Any?
    private var highlightLocalClickMonitor: Any?
    private var highlightAppActivationObserver: NSObjectProtocol?
    private var highlightTargetBundleIdentifier: String?
    private var shouldRestoreAnswerWindowAfterHighlight = false
    private var windowsHiddenForHighlight: [NSWindow] = []
    private var shouldRelaunchAfterTerminate = false
    private var screenRecordingPrimerTask: Task<Void, Never>?
    private var shouldRestoreTranscriptAfterScreenRecordingPrompt = false
    private var shouldRestoreSettingsAfterScreenRecordingPrompt = false
    private var shouldRestoreWindowsAfterAccessibilityPrompt = false
    private var windowsHiddenForSystemPermissionPrompt: [NSWindow] = []
    private var accessibilityPromptRestoreArmingTask: Task<Void, Never>?
    private var appActivationObserver: NSObjectProtocol?
    private var workspaceAppActivationObserver: NSObjectProtocol?
    private var lastExternalApplication: NSRunningApplication?
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
        self.commandWheelController = CommandWheelController()
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
        let savedTranslationSourceLanguage = TranslationSourceLanguage(
            rawValue: defaults.string(forKey: Self.translationSourceLanguageKey) ?? ""
        )
        let availableTranslationSourceLanguages =
            TranslationDirection.availableSourceLanguagesForUserInterface
        self.translationSourceLanguage =
            savedTranslationSourceLanguage.flatMap { savedSourceLanguage in
                availableTranslationSourceLanguages.contains(savedSourceLanguage)
                    ? savedSourceLanguage
                    : nil
            }
            ?? (availableTranslationSourceLanguages.contains(.japanese)
                ? .japanese
                : availableTranslationSourceLanguages[0])
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
        let savedCaptureAndAskHotkeyKeyCode = UInt32(defaults.integer(forKey: Self.captureAndAskHotkeyKeyCodeKey))
        self.captureAndAskHotkeyKeyCode = savedCaptureAndAskHotkeyKeyCode == 0
            ? HotkeyConfiguration.defaultCaptureAndAskConfiguration.keyCode
            : savedCaptureAndAskHotkeyKeyCode
        let savedCaptureAndAskHotkeyModifiers = UInt32(defaults.integer(forKey: Self.captureAndAskHotkeyModifiersKey))
        self.captureAndAskHotkeyModifiers = savedCaptureAndAskHotkeyModifiers == 0
            ? HotkeyConfiguration.defaultCaptureAndAskConfiguration.modifiers
            : savedCaptureAndAskHotkeyModifiers
        let savedTranslateSelectionHotkeyKeyCode = UInt32(defaults.integer(forKey: Self.translateSelectionHotkeyKeyCodeKey))
        let savedTranslateSelectionHotkeyModifiers = UInt32(defaults.integer(forKey: Self.translateSelectionHotkeyModifiersKey))
        let savedTranslateSelectionConfiguration = HotkeyConfiguration(
            keyCode: savedTranslateSelectionHotkeyKeyCode,
            modifiers: savedTranslateSelectionHotkeyModifiers
        )
        let shouldMigrateTranslateSelectionHotkey =
            savedTranslateSelectionHotkeyKeyCode == 0
            || savedTranslateSelectionHotkeyModifiers == 0
            || savedTranslateSelectionConfiguration
                == HotkeyConfiguration.legacyDefaultTranslateSelectionConfiguration
        self.translateSelectionHotkeyKeyCode = shouldMigrateTranslateSelectionHotkey
            ? HotkeyConfiguration.defaultTranslateSelectionConfiguration.keyCode
            : savedTranslateSelectionHotkeyKeyCode
        self.translateSelectionHotkeyModifiers = shouldMigrateTranslateSelectionHotkey
            ? HotkeyConfiguration.defaultTranslateSelectionConfiguration.modifiers
            : savedTranslateSelectionHotkeyModifiers
        let savedTranslateAndReplaceHotkeyKeyCode = UInt32(defaults.integer(forKey: Self.translateAndReplaceHotkeyKeyCodeKey))
        self.translateAndReplaceHotkeyKeyCode = savedTranslateAndReplaceHotkeyKeyCode == 0
            ? HotkeyConfiguration.defaultTranslateAndReplaceConfiguration.keyCode
            : savedTranslateAndReplaceHotkeyKeyCode
        let savedTranslateAndReplaceHotkeyModifiers = UInt32(defaults.integer(forKey: Self.translateAndReplaceHotkeyModifiersKey))
        self.translateAndReplaceHotkeyModifiers = savedTranslateAndReplaceHotkeyModifiers == 0
            ? HotkeyConfiguration.defaultTranslateAndReplaceConfiguration.modifiers
            : savedTranslateAndReplaceHotkeyModifiers
        self.hotkeyDescription = hotkeyConfiguration.displayName
        self.captureAndAskHotkeyDescription = captureAndAskHotkeyConfiguration.displayName
        self.translateSelectionHotkeyDescription = translateSelectionHotkeyConfiguration.displayName
        self.translateAndReplaceHotkeyDescription = translateAndReplaceHotkeyConfiguration.displayName
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
        if captureAndAskHotkeyManager == nil {
            updateCaptureAndAskHotkeyRegistration()
        }
        if translateSelectionHotkeyManager == nil {
            updateTranslateSelectionHotkeyRegistration()
        }
        if translateAndReplaceHotkeyManager == nil {
            updateTranslateAndReplaceHotkeyRegistration()
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
        statusMessage = String(localized: "Screen Recording is enabled in System Settings, but Sasu needs one more relaunch before capture works.")
    }

    private func refreshAccessibilityPermissionState() {
        hasAccessibilityAccess = selectionAutomationService.hasAccessibilityAccess()

        guard hasAccessibilityAccess else {
            if isAwaitingAccessibilityGrant {
                shouldOfferAccessibilityRelaunch = true
                statusMessage = String(localized: "If you enabled Sasu in Accessibility settings, relaunch Sasu for Translate & Replace to work.")
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
        restoreWindowsAfterSystemPermissionPromptIfNeeded()

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
        statusMessage = String(localized: "Welcome to Sasu. Try the example before enabling Screen Recording.")
        answerWindowController.show(appModel: self)
    }

    func showOnboardingGuidance() {
        isOnboardingGuidanceVisible = true
        statusMessage = String(localized: "Sasu can point to the next place to click.")
    }

    func hideOnboardingGuidance() {
        isOnboardingGuidanceVisible = false
        statusMessage = String(localized: "Welcome to Sasu. Try the example before enabling Screen Recording.")
    }

    func completeFirstLaunchOnboarding() {
        DiagnosticLogger.log("First launch onboarding completed. screenRecording=\(CGPreflightScreenCaptureAccess())", category: "Onboarding")
        defaults.set(true, forKey: Self.hasCompletedFirstLaunchOnboardingKey)
        isFirstLaunchOnboardingVisible = false
        isOnboardingGuidanceVisible = false
        statusMessage = String(localized: "Next, enable Screen Recording so Sasu can see the page you ask about.")

        if ScreenRecordingPermissionStore.markGrantConfirmedIfGranted() {
            refreshScreenRecordingPermissionState()
            statusMessage = String(localized: "Screen Recording permission granted. Press \(hotkeyDescription) and choose Capture & Ask.")
            return
        }

        if ScreenRecordingPermissionStore.needsRelaunchForGrantedAccess {
            noteScreenRecordingRelaunchNeeded()
            return
        }

        presentScreenRecordingPrimerIfNeeded()
    }

    func contactDeveloperAboutOnboarding() {
        if let url = Self.developerContactURL(subject: String(localized: "Question about Sasu")) {
            NSWorkspace.shared.open(url)
        }
    }

    private static func developerContactURL(subject: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "justin.garcia@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject)
        ]
        return components.url
    }

    private static func privacyContactLink() -> NSTextField? {
        guard let url = developerContactURL(subject: String(localized: "Privacy question about Sasu")) else {
            return nil
        }

        let text = String(localized: "Have questions about privacy?")
        let attributedText = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .link: url,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        )

        let field = NSTextField(labelWithAttributedString: attributedText)
        field.isSelectable = true
        field.allowsEditingTextAttributes = true
        field.maximumNumberOfLines = 1
        field.frame = NSRect(x: 0, y: 0, width: 180, height: 18)
        return field
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
                guard !settingsWindowController.owns(window) else { return false }

                let identifier = window.identifier?.rawValue.lowercased() ?? ""
                return window.title == String(localized: "Sasu Settings")
                    || identifier.contains("settings")
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
            errorMessage = String(localized: "Paste an OpenAI API key before saving.")
            return
        }

        do {
            try keychain.saveAPIKey(trimmedKey)
            apiKeyInput = ""
            storedAPIKeyPreview = Self.apiKeyPreview(for: trimmedKey)
            hasStoredAPIKey = true
            errorMessage = nil
            statusMessage = String(localized: "OpenAI API key saved in Keychain.")
        } catch {
            errorMessage = String(localized: "Could not save API key: \(error.localizedDescription)")
        }
    }

    func deleteAPIKey() {
        do {
            try keychain.deleteAPIKey()
            hasStoredAPIKey = false
            storedAPIKeyPreview = ""
            errorMessage = nil
            statusMessage = String(localized: "OpenAI API key cleared.")
        } catch {
            errorMessage = String(localized: "Could not clear API key: \(error.localizedDescription)")
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
            statusMessage = String(localized: "Sasu backend access cleared.")
        } catch {
            errorMessage = String(localized: "Could not clear Sasu backend access: \(error.localizedDescription)")
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

        errorMessage = String(localized: "Sasu could not read this link.")
        showSettingsWindowWithStandardOrdering()
    }

    private func redeemInviteCode(_ rawCode: String) {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            errorMessage = String(localized: "Paste an invite code before redeeming.")
            return
        }
        guard let backendBaseURL else {
            errorMessage = AppError.invalidBackendURL.localizedDescription
            return
        }

        isRequestInFlight = true
        errorMessage = nil
        statusMessage = String(localized: "Redeeming invite...")

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
                statusMessage = String(localized: "Invite accepted. Sasu is ready.")
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = String(localized: "Could not redeem invite.")
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
        statusMessage = String(localized: "Model reset to \(ModelPreset.gpt56HighFast.label).")
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

    func setHotkeyModifier(_ modifier: UInt32, enabled: Bool) {
        if enabled {
            hotkeyModifiers |= modifier
        } else {
            let updatedModifiers = hotkeyModifiers & ~modifier
            guard updatedModifiers != 0 else {
                errorMessage = String(localized: "Choose at least one modifier for the global hotkey.")
                return
            }

            hotkeyModifiers = updatedModifiers
        }
    }

    func resetHotkeyToDefault() {
        hotkeyKeyCode = HotkeyConfiguration.defaultConfiguration.keyCode
        hotkeyModifiers = HotkeyConfiguration.defaultConfiguration.modifiers
        statusMessage = String(localized: "Command wheel hotkey reset to \(hotkeyDescription).")
    }

    func setCaptureAndAskHotkeyModifier(_ modifier: UInt32, enabled: Bool) {
        if enabled {
            captureAndAskHotkeyModifiers |= modifier
        } else {
            let updatedModifiers = captureAndAskHotkeyModifiers & ~modifier
            guard updatedModifiers != 0 else {
                errorMessage = String(localized: "Choose at least one modifier for the Capture & Ask hotkey.")
                return
            }

            captureAndAskHotkeyModifiers = updatedModifiers
        }
    }

    func resetCaptureAndAskHotkeyToDefault() {
        captureAndAskHotkeyKeyCode = HotkeyConfiguration.defaultCaptureAndAskConfiguration.keyCode
        captureAndAskHotkeyModifiers = HotkeyConfiguration.defaultCaptureAndAskConfiguration.modifiers
        statusMessage = String(localized: "Capture & Ask hotkey reset to \(captureAndAskHotkeyDescription).")
    }

    func setTranslateSelectionHotkeyModifier(_ modifier: UInt32, enabled: Bool) {
        if enabled {
            translateSelectionHotkeyModifiers |= modifier
        } else {
            let updatedModifiers = translateSelectionHotkeyModifiers & ~modifier
            guard updatedModifiers != 0 else {
                errorMessage = String(localized: "Choose at least one modifier for the Translate Selection hotkey.")
                return
            }

            translateSelectionHotkeyModifiers = updatedModifiers
        }
    }

    func resetTranslateSelectionHotkeyToDefault() {
        translateSelectionHotkeyKeyCode = HotkeyConfiguration.defaultTranslateSelectionConfiguration.keyCode
        translateSelectionHotkeyModifiers = HotkeyConfiguration.defaultTranslateSelectionConfiguration.modifiers
        statusMessage = String(localized: "Translate Selection hotkey reset to \(translateSelectionHotkeyDescription).")
    }

    func setTranslateAndReplaceHotkeyModifier(_ modifier: UInt32, enabled: Bool) {
        if enabled {
            translateAndReplaceHotkeyModifiers |= modifier
        } else {
            let updatedModifiers = translateAndReplaceHotkeyModifiers & ~modifier
            guard updatedModifiers != 0 else {
                errorMessage = String(localized: "Choose at least one modifier for the Translate & Replace hotkey.")
                return
            }

            translateAndReplaceHotkeyModifiers = updatedModifiers
        }
    }

    func resetTranslateAndReplaceHotkeyToDefault() {
        translateAndReplaceHotkeyKeyCode =
            HotkeyConfiguration.defaultTranslateAndReplaceConfiguration.keyCode
        translateAndReplaceHotkeyModifiers =
            HotkeyConfiguration.defaultTranslateAndReplaceConfiguration.modifiers
        statusMessage = String(localized: "Translate & Replace hotkey reset to \(translateAndReplaceHotkeyDescription).")
    }

    func captureAndAsk() {
        guard !isRequestInFlight else { return }
        guard !isFirstLaunchOnboardingVisible else {
            statusMessage = String(localized: "Click Sasuを始める in the example to enable Screen Recording first.")
            return
        }

        currentRequestTask = Task {
            await prepareScreenshotForQuery()
        }
    }

    func showCommandWheel() {
        let sourceApplication = NSWorkspace.shared.frontmostApplication
        commandWheelController.presentOrAdvance(
            hotkeyModifiers: hotkeyModifiers
        ) { [weak self] command in
            guard let self else { return }
            switch command {
            case .captureAndAsk:
                captureAndAsk()
            case .translateSelection:
                translateVisibleSelection(sourceApplication: sourceApplication)
            case .translateAndReplace:
                translateAndReplaceSelection(sourceApplication: sourceApplication)
            }
        }
    }

    func translateVisibleSelection(sourceApplication: NSRunningApplication? = nil) {
        guard !isRequestInFlight else { return }
        guard !isFirstLaunchOnboardingVisible else {
            statusMessage = String(localized: "Click Sasuを始める in the example to enable Screen Recording first.")
            return
        }

        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let invokedWhileSasuIsFrontmost = frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        let selectionSourceApplication = sourceApplication.flatMap { isSasuApplication($0) ? nil : $0 }
            ?? (invokedWhileSasuIsFrontmost ? lastExternalApplication : frontmostApplication)

        if selectionAutomationService.hasAccessibilityAccess() {
            selectionSourceApplication?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            currentRequestTask = Task {
                if invokedWhileSasuIsFrontmost {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
                await runTranslateSelectedText(fallbackToClipboard: invokedWhileSasuIsFrontmost)
            }
            return
        }

        let sourceApplication = selectionSourceApplication
        switch presentTranslateSelectionAccessibilityPrimerIfNeeded() {
        case .proceed:
            requestAccessibilityAccess()
            return
        case .notNow, .dontAskAgain:
            sourceApplication?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        case .notNeeded:
            break
        }

        let direction = TranslationDirection.forUserInterface(
            sourceLanguage: translationSourceLanguage
        )
        let prompt = """
        Translate only the text that is visibly selected or highlighted on screen. The user's language pair is \(direction.expectedSourceLanguage) and \(direction.targetLanguage). Detect which of those two languages the selected text is written in, then translate it into the other language. Put the exact selected original text in sourceText and return the translation clearly in answer. If no text is visibly selected, set sourceText to null and say that no selected text could be found.
        """

        currentRequestTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            await runCapture(
                prompt: prompt,
                mode: .visibleSelectionTranslation
            )
        }
    }

    func translateClipboard() {
        guard !isRequestInFlight else { return }
        guard !isFirstLaunchOnboardingVisible else {
            statusMessage = String(localized: "Click Sasuを始める in the example to enable Screen Recording first.")
            return
        }

        currentRequestTask = Task {
            await runTranslateClipboard()
        }
    }

    func translateAndReplaceSelection(sourceApplication: NSRunningApplication? = nil) {
        guard !isRequestInFlight else { return }
        guard !isFirstLaunchOnboardingVisible else {
            statusMessage = String(localized: "Click Sasuを始める in the example to enable Screen Recording first.")
            return
        }

        guard selectionAutomationService.hasAccessibilityAccess() else {
            guard presentEditableSelectionAccessibilityPrimer() else {
                statusMessage = String(localized: "Translate & Replace was cancelled.")
                return
            }
            requestAccessibilityAccess()
            return
        }

        sourceApplication?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        currentRequestTask = Task {
            await runTranslateSelection()
        }
    }

    func sendFollowUp() {
        guard !isFirstLaunchOnboardingVisible else {
            statusMessage = String(localized: "Click Sasuを始める in the example to enable Screen Recording first.")
            return
        }
        let followUp = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !followUp.isEmpty else { return }
        guard lastScreenshot != nil else {
            errorMessage = String(localized: "Capture the screen before sending a follow-up.")
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
        streamingResponseText = ""
        cursorProgressOverlayController.hide()
        statusMessage = String(localized: "Request stopped.")
        errorMessage = nil
        transcriptMessages.append(ChatTranscriptMessage(role: .error, text: String(localized: "Request stopped.")))
        Self.logger.info("User cancelled current request.")
    }

    func copyLastAnswerToPasteboard() {
        guard let text = lastResponse?.text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = String(localized: "Answer copied to clipboard.")
    }

    func copyTranscriptToPasteboard() {
        let transcript = transcriptMessages
            .map { "\($0.role.displayLabel):\n\($0.localizedTranscriptText)" }
            .joined(separator: "\n\n")
        guard !transcript.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
        statusMessage = String(localized: "Transcript copied to clipboard.")
    }

    func clearTranscript() {
        transcriptMessages.removeAll()
        lastResponse = nil
        errorMessage = nil
        shouldOfferPermissionRelaunch = false
        currentHighlightSuggestion = nil
        hideHighlight()
        statusMessage = String(localized: "Transcript cleared.")
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
            errorMessage = String(localized: "Could not open screenshot preview.")
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
                self.startHighlightAppSwitchMonitoring(
                    targetBundleIdentifier: lastScreenshot.frontmostApplicationBundleIdentifier
                )
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
        restoreWhenAppActivates: Bool = false,
        immediately: Bool = false
    ) {
        highlightAutoHideTask?.cancel()
        highlightAutoHideTask = nil
        highlightClickMonitorStartTask?.cancel()
        highlightClickMonitorStartTask = nil
        stopHighlightClickMonitoring()
        stopHighlightAppSwitchMonitoring()
        highlightOverlayController.hide(immediately: immediately)
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
        if appActivationObserver == nil {
            appActivationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.cancelUserAttentionRequestIfNeeded()
                    self?.closeUnmanagedSettingsWindows()
                    self?.restoreHighlightWindowsAfterUserReturn()
                    self?.restoreWindowsAfterSystemPermissionPromptIfNeeded()
                    self?.refreshAccessibilityPermissionState()
                    self?.refreshScreenRecordingPermissionState()
                }
            }
        }

        guard workspaceAppActivationObserver == nil else { return }
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           !isSasuApplication(frontmostApplication) {
            lastExternalApplication = frontmostApplication
        }
        workspaceAppActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }

            Task { @MainActor in
                guard let self, !self.isSasuApplication(application) else { return }
                self.lastExternalApplication = application
            }
        }
    }

    private func isSasuApplication(_ application: NSRunningApplication) -> Bool {
        application.processIdentifier == ProcessInfo.processInfo.processIdentifier
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

    private func startHighlightAppSwitchMonitoring(targetBundleIdentifier: String?) {
        stopHighlightAppSwitchMonitoring()
        highlightTargetBundleIdentifier = targetBundleIdentifier
        highlightAppActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            Task { @MainActor in
                guard let self, self.isHighlightVisible else { return }
                guard let targetBundleIdentifier = self.highlightTargetBundleIdentifier else {
                    self.highlightTargetBundleIdentifier = application.bundleIdentifier
                    return
                }
                guard application.bundleIdentifier != targetBundleIdentifier else { return }
                self.hideHighlight(restoreWhenAppActivates: true, immediately: true)
            }
        }
    }

    private func stopHighlightAppSwitchMonitoring() {
        if let highlightAppActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(highlightAppActivationObserver)
            self.highlightAppActivationObserver = nil
        }
        highlightTargetBundleIdentifier = nil
    }

    func openScreenRecordingSettings() {
        ScreenRecordingPermissionStore.markSetupStarted()
        shouldOfferPermissionRelaunch = false

        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"),
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")
        ].compactMap { $0 }

        statusMessage = String(localized: "Opened Screen Recording settings. Enable Sasu, then relaunch Sasu.")

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

        errorMessage = String(localized: "Open System Settings > Privacy & Security > Screen Recording, then enable Sasu.")
    }

    func openAccessibilitySettings() {
        isAwaitingAccessibilityGrant = true
        shouldOfferAccessibilityRelaunch = false

        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")
        ].compactMap { $0 }

        statusMessage = String(localized: "Opened Accessibility settings. Enable Sasu, then relaunch Sasu.")

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

        errorMessage = String(localized: "Open System Settings > Privacy & Security > Accessibility, then enable Sasu.")
    }

    func openAutomationSettings() {
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"),
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")
        ].compactMap { $0 }

        statusMessage = String(localized: "Opened Automation settings. Enable Safari under Sasu, then capture Safari again.")

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

        errorMessage = String(localized: "Open System Settings > Privacy & Security > Automation, then enable Safari under Sasu.")
    }

    func requestAccessibilityAccess() {
        isAwaitingAccessibilityGrant = true
        shouldOfferAccessibilityRelaunch = false
        accessibilityPromptRestoreArmingTask?.cancel()
        shouldRestoreWindowsAfterAccessibilityPrompt = false
        hideWindowsForSystemPermissionPrompt()
        selectionAutomationService.requestAccessibilityAccess()
        accessibilityPromptRestoreArmingTask = Task { @MainActor [weak self] in
            // The activation notification generated by Sasu's own explanation
            // can arrive after the native AX prompt opens. Ignore that stale
            // notification so it cannot restore Sasu above the system dialog.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.shouldRestoreWindowsAfterAccessibilityPrompt = true
        }
        statusMessage = String(localized: "Approve the macOS Accessibility prompt, or enable Sasu in System Settings, then relaunch Sasu.")
        refreshAccessibilityPermissionState()
    }

    private enum TranslateSelectionAccessibilityDecision {
        case proceed
        case notNow
        case dontAskAgain
        case notNeeded
    }

    private func presentTranslateSelectionAccessibilityPrimerIfNeeded()
        -> TranslateSelectionAccessibilityDecision {
        if defaults.bool(forKey: Self.suppressTranslateSelectionAccessibilityPrimerKey)
            || defaults.bool(forKey: Self.hasAnsweredTranslateSelectionAccessibilityPrimerKey) {
            return .notNeeded
        }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Translate Selected Text Faster?")
        alert.informativeText = String(localized: """
        With Accessibility permission, Translate Selection can copy highlighted text directly instead of taking a screenshot. This makes translations faster and avoids sending a screenshot.

        Accessibility also enables Translate & Replace, which can replace editable selections in place. Sasu uses this access only when you choose one of those commands.
        """)
        alert.addButton(withTitle: String(localized: "Proceed"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        alert.addButton(withTitle: String(localized: "Don’t Ask Again"))
        alert.accessoryView = Self.privacyContactLink()

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            defaults.set(
                true,
                forKey: Self.hasAnsweredTranslateSelectionAccessibilityPrimerKey
            )
            DiagnosticLogger.log(
                "User continued to Accessibility access from Translate Selection.",
                category: "Permissions"
            )
            return .proceed
        case .alertThirdButtonReturn:
            defaults.set(
                true,
                forKey: Self.suppressTranslateSelectionAccessibilityPrimerKey
            )
            DiagnosticLogger.log(
                "User suppressed the Translate Selection Accessibility explanation.",
                category: "Permissions"
            )
            return .dontAskAgain
        default:
            DiagnosticLogger.log(
                "User postponed Accessibility access from Translate Selection.",
                category: "Permissions"
            )
            return .notNow
        }
    }

    private func presentEditableSelectionAccessibilityPrimer() -> Bool {
        if defaults.bool(forKey: Self.hasAcknowledgedTranslateAndReplaceAccessibilityPrimerKey) {
            return true
        }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Enable Translate & Replace?")
        alert.informativeText = String(localized: """
        Translate & Replace copies selected text from the app you are editing, translates it into your chosen language, and replaces the selection in place.

        macOS requires Accessibility permission so Sasu can send Copy and Paste commands. Sasu uses this access only when you choose Translate Selection or Translate & Replace. Translate Selection can still fall back to a screenshot if you do not grant access.
        """)
        alert.addButton(withTitle: String(localized: "Proceed"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        alert.accessoryView = Self.privacyContactLink()

        guard alert.runModal() == .alertFirstButtonReturn else {
            DiagnosticLogger.log(
                "User postponed Accessibility access for Translate & Replace.",
                category: "Permissions"
            )
            return false
        }

        defaults.set(
            true,
            forKey: Self.hasAcknowledgedTranslateAndReplaceAccessibilityPrimerKey
        )
        DiagnosticLogger.log(
            "User continued to Accessibility access for Translate & Replace.",
            category: "Permissions"
        )
        return true
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
            alert.messageText = String(localized: "Sasu Needs Screen Recording")
            alert.informativeText = String(localized: """
            Sasu captures your screen only when you choose Capture & Ask or Capture Screen, then sends that screenshot to OpenAI with your question.

            macOS requires Screen Recording permission before Sasu can see the page or app you want help with.
            """)
            alert.addButton(withTitle: String(localized: "Accept Screen Recording"))
            alert.addButton(withTitle: String(localized: "Not Yet"))
            alert.accessoryView = Self.privacyContactLink()

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
            statusMessage = String(localized: "Screen Recording permission granted. Press \(hotkeyDescription) and choose Capture & Ask.")
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

        statusMessage = String(localized: "Waiting for Screen Recording permission...")
        _ = CGRequestScreenCaptureAccess()

        if ScreenRecordingPermissionStore.markGrantConfirmedIfGranted() {
            DiagnosticLogger.log("Screen Recording permission granted immediately.", category: "Permissions")
            refreshScreenRecordingPermissionState()
            statusMessage = String(localized: "Screen Recording permission granted. Press \(hotkeyDescription) and choose Capture & Ask.")
            restoreWindowsAfterScreenRecordingPrompt()
        } else {
            DiagnosticLogger.log("Screen Recording permission not granted after request.", category: "Permissions")
            statusMessage = String(localized: "Approve the macOS Screen Recording prompt. If you do not see it, use Open Screen Recording Settings.")
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
        let newlyHiddenWindows = Self.hideVisibleSasuWindowsForCapture()
        for window in newlyHiddenWindows
        where !windowsHiddenForSystemPermissionPrompt.contains(where: { $0 === window }) {
            windowsHiddenForSystemPermissionPrompt.append(window)
        }
    }

    private func restoreWindowsAfterSystemPermissionPromptIfNeeded() {
        let wasWaitingForScreenRecording = shouldRestoreTranscriptAfterScreenRecordingPrompt
            || shouldRestoreSettingsAfterScreenRecordingPrompt
        guard wasWaitingForScreenRecording
            || shouldRestoreWindowsAfterAccessibilityPrompt
        else { return }

        if wasWaitingForScreenRecording,
           ScreenRecordingPermissionStore.markGrantConfirmedIfGranted() {
            refreshScreenRecordingPermissionState()
            statusMessage = String(localized: "Screen Recording permission granted. Press \(hotkeyDescription) and choose Capture & Ask.")
        }

        restoreWindowsAfterScreenRecordingPrompt()
    }

    private func restoreWindowsAfterScreenRecordingPrompt() {
        if !windowsHiddenForSystemPermissionPrompt.isEmpty {
            Self.restoreWindows(windowsHiddenForSystemPermissionPrompt)
        } else if shouldRestoreSettingsAfterScreenRecordingPrompt {
            showSettingsWindowWithStandardOrdering()
        } else if shouldRestoreTranscriptAfterScreenRecordingPrompt {
            answerWindowController.show(appModel: self)
        }

        windowsHiddenForSystemPermissionPrompt.removeAll()
        accessibilityPromptRestoreArmingTask?.cancel()
        accessibilityPromptRestoreArmingTask = nil
        shouldRestoreTranscriptAfterScreenRecordingPrompt = false
        shouldRestoreSettingsAfterScreenRecordingPrompt = false
        shouldRestoreWindowsAfterAccessibilityPrompt = false
    }

    func relaunchSasu() {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            errorMessage = String(localized: "Quit this process and launch Sasu from Build/Sasu.app so macOS applies permission changes to the app bundle.")
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

    private var captureAndAskHotkeyConfiguration: HotkeyConfiguration {
        HotkeyConfiguration(
            keyCode: captureAndAskHotkeyKeyCode,
            modifiers: captureAndAskHotkeyModifiers
        )
    }

    private var translateSelectionHotkeyConfiguration: HotkeyConfiguration {
        HotkeyConfiguration(
            keyCode: translateSelectionHotkeyKeyCode,
            modifiers: translateSelectionHotkeyModifiers
        )
    }

    private var translateAndReplaceHotkeyConfiguration: HotkeyConfiguration {
        HotkeyConfiguration(
            keyCode: translateAndReplaceHotkeyKeyCode,
            modifiers: translateAndReplaceHotkeyModifiers
        )
    }

    private var hotkeyReadinessMessage: String {
        String(localized: "Ready. Use \(hotkeyDescription) for the command wheel.")
    }

    private func updateHotkeyRegistration() {
        hotkeyManager?.unregister()
        hotkeyManager = nil

        hotkeyDescription = hotkeyConfiguration.displayName
        let manager = HotkeyManager(configuration: hotkeyConfiguration, identifier: 1) { [weak self] in
            Task { @MainActor in
                self?.showCommandWheel()
            }
        }

        do {
            try manager.register()
            hotkeyManager = manager
            errorMessage = nil
            statusMessage = hotkeyReadinessMessage
        } catch {
            errorMessage = String(localized: "Could not register \(hotkeyDescription): \(error.localizedDescription)")
            statusMessage = String(localized: "Use the Sasu menu while the command wheel hotkey is unavailable.")
        }
    }

    private func updateCaptureAndAskHotkeyRegistration() {
        captureAndAskHotkeyManager?.unregister()
        captureAndAskHotkeyManager = nil

        captureAndAskHotkeyDescription = captureAndAskHotkeyConfiguration.displayName
        let manager = HotkeyManager(configuration: captureAndAskHotkeyConfiguration, identifier: 2) { [weak self] in
            Task { @MainActor in
                self?.captureAndAsk()
            }
        }

        do {
            try manager.register()
            captureAndAskHotkeyManager = manager
            errorMessage = nil
            statusMessage = hotkeyReadinessMessage
        } catch {
            errorMessage = String(localized: "Could not register \(captureAndAskHotkeyDescription): \(error.localizedDescription)")
            statusMessage = String(localized: "Use Capture & Ask from the app while the hotkey is unavailable.")
        }
    }

    private func updateTranslateSelectionHotkeyRegistration() {
        translateSelectionHotkeyManager?.unregister()
        translateSelectionHotkeyManager = nil

        translateSelectionHotkeyDescription = translateSelectionHotkeyConfiguration.displayName
        let manager = HotkeyManager(configuration: translateSelectionHotkeyConfiguration, identifier: 3) { [weak self] in
            Task { @MainActor in
                self?.translateVisibleSelection()
            }
        }

        do {
            try manager.register()
            translateSelectionHotkeyManager = manager
            errorMessage = nil
            statusMessage = hotkeyReadinessMessage
        } catch {
            errorMessage = String(localized: "Could not register \(translateSelectionHotkeyDescription): \(error.localizedDescription)")
            statusMessage = String(localized: "Use Translate Selection from the app while the hotkey is unavailable.")
        }
    }

    private func updateTranslateAndReplaceHotkeyRegistration() {
        translateAndReplaceHotkeyManager?.unregister()
        translateAndReplaceHotkeyManager = nil

        translateAndReplaceHotkeyDescription = translateAndReplaceHotkeyConfiguration.displayName
        let manager = HotkeyManager(
            configuration: translateAndReplaceHotkeyConfiguration,
            identifier: 4
        ) { [weak self] in
            Task { @MainActor in
                self?.translateAndReplaceSelection()
            }
        }

        do {
            try manager.register()
            translateAndReplaceHotkeyManager = manager
            errorMessage = nil
            statusMessage = hotkeyReadinessMessage
        } catch {
            errorMessage = String(localized: "Could not register \(translateAndReplaceHotkeyDescription): \(error.localizedDescription)")
            statusMessage = String(localized: "Use Translate & Replace from the app while the hotkey is unavailable.")
        }
    }

    private func prepareScreenshotForQuery() async {
        isRequestInFlight = true
        errorMessage = nil
        shouldOfferPermissionRelaunch = false
        statusMessage = String(localized: "Capturing screen...")
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
                ? (screenshot.browserPageContext == nil
                    ? String(localized: "Explain this")
                    : String(localized: "Explain this page"))
                : String(localized: "What now?")
            querySelectionNonce += 1
            currentHighlightSuggestion = nil
            hideHighlight()
            if let browserPageContext = screenshot.browserPageContext {
                statusMessage = String(localized: "Screenshot and Safari page ready. Type your question and press Send.")
                Self.logger.info("Prepared screenshot with Safari page. bytes=\(screenshot.pngData.count), pixelWidth=\(Int(screenshot.pixelSize.width)), pixelHeight=\(Int(screenshot.pixelSize.height)), pageCharacters=\(browserPageContext.text.count)")
            } else if screenshot.browserPageCaptureIssue != nil {
                statusMessage = String(localized: "Screenshot ready, but Safari page content was not included.")
                Self.logger.info("Prepared screenshot without Safari page after attempted Safari capture. bytes=\(screenshot.pngData.count), pixelWidth=\(Int(screenshot.pixelSize.width)), pixelHeight=\(Int(screenshot.pixelSize.height))")
            } else {
                statusMessage = String(localized: "Screenshot ready. Type your question and press Send.")
                Self.logger.info("Prepared screenshot. bytes=\(screenshot.pngData.count), pixelWidth=\(Int(screenshot.pixelSize.width)), pixelHeight=\(Int(screenshot.pixelSize.height))")
            }
        } catch is CancellationError {
            statusMessage = String(localized: "Capture stopped.")
            errorMessage = nil
            Self.logger.info("Screenshot preparation cancelled.")
        } catch {
            errorMessage = error.localizedDescription
            shouldOfferPermissionRelaunch = (error as? ScreenshotError) == .permissionDenied
            statusMessage = String(localized: "Something went wrong.")
            transcriptMessages.append(ChatTranscriptMessage(role: .error, text: error.localizedDescription))
            Self.logger.error("Screenshot preparation failed: \(error.localizedDescription, privacy: .public)")
        }

        isRequestInFlight = false
        currentRequestTask = nil
        answerWindowController.show(appModel: self)
    }

    private func runTranslateClipboard() async {
        isRequestInFlight = true
        streamingResponseText = ""
        errorMessage = nil
        shouldOfferPermissionRelaunch = false
        currentHighlightSuggestion = nil
        hideHighlight()
        statusMessage = String(localized: "Reading clipboard...")
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
                text: sourceText,
                sourceReadings: sourceReadings,
                sourceKind: .clipboard
            )
            transcriptMessages.append(sourceMessage)

            try Task.checkCancellation()
            let credential = try requestCredential()

            statusMessage = String(localized: "Translating clipboard...")
            cursorProgressOverlayController.show(status: String(localized: "Translating…"))
            answerWindowController.show(appModel: self)
            let result = try await openAIClient.translateClipboardText(
                credential: credential,
                modelID: modelID,
                reasoningEffort: reasoningEffort,
                serviceTier: serviceTier,
                sourceText: sourceText,
                translationDirection: TranslationDirection.forUserInterface(
                    sourceLanguage: translationSourceLanguage
                ),
                conversationContext: conversationContext,
                onPartialAnswer: { [weak self] partialAnswer in
                    await self?.receiveStreamedAnswer(partialAnswer)
                }
            )
            try Task.checkCancellation()
            let translation = Self.normalizedTranslationText(result)

            lastResponse = AssistantResponse(
                text: translation,
                prompt: "Translate clipboard",
                actionSuggestion: nil
            )
            transcriptMessages.append(ChatTranscriptMessage(role: .assistant, text: translation))
            statusMessage = String(localized: "Clipboard translation ready.")
            DiagnosticLogger.log("Clipboard translation ready. sourceCharacters=\(sourceText.count) localSegmentsWithReadings=\(readingCount)", category: "OpenAI")
            Self.logger.info("Clipboard translation ready. sourceCharacters=\(sourceText.count), answerCharacters=\(translation.count), localSegmentsWithReadings=\(readingCount)")
        } catch is CancellationError {
            statusMessage = String(localized: "Request stopped.")
            errorMessage = nil
            Self.logger.info("Clipboard translation cancelled.")
        } catch {
            errorMessage = error.localizedDescription
            transcriptMessages.append(ChatTranscriptMessage(role: .error, text: error.localizedDescription))
            statusMessage = String(localized: "Something went wrong.")
            Self.logger.error("Clipboard translation failed: \(error.localizedDescription, privacy: .public)")
        }

        isRequestInFlight = false
        streamingResponseText = ""
        cursorProgressOverlayController.hide()
        currentRequestTask = nil
        let shouldActivateAnswerWindow = NSApp.isActive
        answerWindowController.show(appModel: self, activate: shouldActivateAnswerWindow)
        if !shouldActivateAnswerWindow {
            requestUserAttentionIfNeeded()
        }
    }

    private func runTranslateSelectedText(fallbackToClipboard: Bool = false) async {
        isRequestInFlight = true
        streamingResponseText = ""
        errorMessage = nil
        currentHighlightSuggestion = nil
        hideHighlight()
        statusMessage = String(localized: "Reading selected text...")
        cursorProgressOverlayController.show(status: String(localized: "Reading selection…"))

        var pasteboardBackup: PasteboardBackup?

        do {
            try Task.checkCancellation()
            let sourceText: String
            do {
                let copiedSelection = try await selectionAutomationService.copySelectedText()
                pasteboardBackup = copiedSelection.backup
                sourceText = copiedSelection.text
                copiedSelection.backup.restore()
                pasteboardBackup = nil
            } catch SelectionAutomationError.noSelection where fallbackToClipboard {
                sourceText = try clipboardTextService.readText()
                statusMessage = String(localized: "No selection found in the previous app. Translating clipboard...")
            } catch SelectionAutomationError.emptySelection where fallbackToClipboard {
                sourceText = try clipboardTextService.readText()
                statusMessage = String(localized: "No selection found in the previous app. Translating clipboard...")
            }

            let sourceReadings = translationSourceLanguage == .japanese
                ? JapaneseReadingService.readings(for: sourceText)
                : nil
            transcriptMessages.append(
                ChatTranscriptMessage(
                    role: .user,
                    text: sourceText,
                    sourceReadings: sourceReadings,
                    sourceKind: .selection
                )
            )

            try Task.checkCancellation()
            let credential = try requestCredential()
            statusMessage = String(localized: "Translating selected text...")
            cursorProgressOverlayController.update(status: String(localized: "Translating…"))
            answerWindowController.show(appModel: self)

            let result = try await openAIClient.translateClipboardText(
                credential: credential,
                modelID: modelID,
                reasoningEffort: reasoningEffort,
                serviceTier: serviceTier,
                sourceText: sourceText,
                translationDirection: TranslationDirection.forUserInterface(
                    sourceLanguage: translationSourceLanguage
                ),
                conversationContext: nil,
                onPartialAnswer: { [weak self] partialAnswer in
                    await self?.receiveStreamedAnswer(partialAnswer)
                }
            )
            try Task.checkCancellation()

            let translation = Self.normalizedTranslationText(result)
            lastResponse = AssistantResponse(
                text: translation,
                prompt: "Translate selection",
                actionSuggestion: nil
            )
            transcriptMessages.append(
                ChatTranscriptMessage(role: .assistant, text: translation)
            )
            statusMessage = String(localized: "Translation ready.")
            DiagnosticLogger.log(
                "Selected text translation ready. sourceCharacters=\(sourceText.count)",
                category: "OpenAI"
            )
        } catch is CancellationError {
            pasteboardBackup?.restore()
            statusMessage = String(localized: "Request stopped.")
            errorMessage = nil
        } catch {
            pasteboardBackup?.restore()
            errorMessage = error.localizedDescription
            transcriptMessages.append(
                ChatTranscriptMessage(role: .error, text: error.localizedDescription)
            )
            statusMessage = String(localized: "Translation failed.")
            let diagnostic = "Selected text translation failed. errorType=\(String(reflecting: type(of: error))) description=\(error.localizedDescription)"
            DiagnosticLogger.log(diagnostic, category: "OpenAI")
            Self.logger.error("\(diagnostic, privacy: .public)")
            requestUserAttentionIfNeeded()
        }

        isRequestInFlight = false
        streamingResponseText = ""
        cursorProgressOverlayController.hide()
        currentRequestTask = nil
        let shouldActivateAnswerWindow = NSApp.isActive
        answerWindowController.show(appModel: self, activate: shouldActivateAnswerWindow)
        if !shouldActivateAnswerWindow {
            requestUserAttentionIfNeeded()
        }
    }

    private func runTranslateSelection() async {
        isRequestInFlight = true
        cursorProgressOverlayController.show(status: String(localized: "Translating selection…"))
        defer {
            cursorProgressOverlayController.hide()
        }

        errorMessage = nil
        shouldOfferPermissionRelaunch = false
        statusMessage = String(localized: "Translating selection...")
        Self.logger.info("Starting selection translation flow. model=\(self.modelID, privacy: .public), reasoning=\(self.reasoningEffort, privacy: .public), serviceTier=\(self.serviceTier, privacy: .public)")

        var pasteboardBackup: PasteboardBackup?

        do {
            try Task.checkCancellation()

            guard selectionAutomationService.hasAccessibilityAccess() else {
                requestAccessibilityAccess()
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
                translationDirection: TranslationDirection.forEditableSelectionReplacement(
                    sourceLanguage: translationSourceLanguage
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

            statusMessage = String(localized: "Selection translated.")
            Self.logger.info("Selection translation ready. sourceCharacters=\(sourceText.count), answerCharacters=\(translation.count)")
        } catch is CancellationError {
            if let pasteboardBackup {
                pasteboardBackup.restore()
            }
            statusMessage = String(localized: "Request stopped.")
            errorMessage = nil
            Self.logger.info("Selection translation cancelled.")
        } catch {
            if let pasteboardBackup {
                pasteboardBackup.restore()
            }
            errorMessage = error.localizedDescription
            statusMessage = String(localized: "Selection translation failed.")
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

    private enum CaptureRequestMode {
        case question
        case visibleSelectionTranslation

        var showsCaptureDetailsInTranscript: Bool {
            self == .question
        }

        var includesSafariPageContext: Bool {
            self == .question
        }
    }

    private func runCapture(
        prompt: String,
        reuseLastScreenshot: Bool = false,
        mode: CaptureRequestMode = .question
    ) async {
        isRequestInFlight = true
        streamingResponseText = ""
        errorMessage = nil
        shouldOfferPermissionRelaunch = false
        statusMessage = mode == .visibleSelectionTranslation
            ? String(localized: "Reading visible selection...")
            : (reuseLastScreenshot
                ? String(localized: "Sending follow-up...")
                : String(localized: "Capturing screen..."))
        Self.logger.info("Starting capture flow. reuseLastScreenshot=\(reuseLastScreenshot), model=\(self.modelID, privacy: .public), reasoning=\(self.reasoningEffort, privacy: .public), serviceTier=\(self.serviceTier, privacy: .public), imageDetail=\(self.imageDetail, privacy: .public)")
        let conversationContext = mode == .question ? transcriptContextForRequest() : nil
        if mode.showsCaptureDetailsInTranscript {
            transcriptMessages.append(ChatTranscriptMessage(role: .user, text: prompt))
        }

        do {
            try Task.checkCancellation()
            let credential = try requestCredential()

            var screenshot: ScreenshotPayload
            if reuseLastScreenshot, let existingScreenshot = lastScreenshot {
                screenshot = existingScreenshot
            } else {
                try Task.checkCancellation()
                let capturedScreenshot = try await captureMainDisplayWithSasuWindowsHidden()
                screenshot = mode.includesSafariPageContext
                    ? await screenshotIncludingSafariPageContextIfNeeded(capturedScreenshot)
                    : capturedScreenshot
                lastScreenshot = screenshot
                screenshotPreviewImage = NSImage(data: screenshot.pngData)
                isScreenshotPrepared = true
                if mode.showsCaptureDetailsInTranscript {
                    appendScreenshotMessage(for: screenshot)
                }
            }
            try Task.checkCancellation()
            screenshot = confirmLargeSafariPageContextBeforeSending(screenshot)
            try Task.checkCancellation()
            Self.logger.info("Screenshot ready. bytes=\(screenshot.pngData.count), pixelWidth=\(Int(screenshot.pixelSize.width)), pixelHeight=\(Int(screenshot.pixelSize.height))")

            statusMessage = String(localized: "Asking OpenAI...")
            cursorProgressOverlayController.show(status: String(localized: "Asking OpenAI…"))
            answerWindowController.show(appModel: self)
            let result = try await openAIClient.askAboutScreenshot(
                credential: credential,
                modelID: modelID,
                reasoningEffort: reasoningEffort,
                serviceTier: serviceTier,
                imageDetail: imageDetail,
                translationSourceLanguage: translationSourceLanguage,
                prompt: prompt,
                screenshot: screenshot,
                conversationContext: conversationContext,
                onPartialAnswer: { [weak self] partialAnswer in
                    await self?.receiveStreamedAnswer(partialAnswer)
                }
            )
            try Task.checkCancellation()
            let actionSuggestion = mode == .question
                ? await groundedSuggestion(result.actionSuggestion, screenshot: screenshot)
                : nil
            try Task.checkCancellation()
            let answer = Self.normalizedAnswerText(result.answer)

            if mode == .visibleSelectionTranslation,
               let sourceText = result.sourceText?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !sourceText.isEmpty {
                let sourceReadings = JapaneseReadingService.readings(for: sourceText)
                transcriptMessages.append(
                    ChatTranscriptMessage(
                        role: .user,
                        text: sourceText,
                        sourceReadings: sourceReadings,
                        sourceKind: .selection
                    )
                )
            }

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
            statusMessage = mode == .visibleSelectionTranslation
                ? String(localized: "Translation ready.")
                : String(localized: "Answer ready.")
            Self.logger.info("OpenAI answer ready. characters=\(answer.count), hasHighlight=\(actionSuggestion != nil)")
        } catch is CancellationError {
            statusMessage = String(localized: "Request stopped.")
            errorMessage = nil
            Self.logger.info("Capture flow cancelled.")
        } catch {
            errorMessage = error.localizedDescription
            transcriptMessages.append(ChatTranscriptMessage(role: .error, text: error.localizedDescription))
            shouldOfferPermissionRelaunch = (error as? ScreenshotError) == .permissionDenied
            statusMessage = String(localized: "Something went wrong.")
            Self.logger.error("Capture flow failed: \(error.localizedDescription, privacy: .public)")
        }

        isRequestInFlight = false
        streamingResponseText = ""
        cursorProgressOverlayController.hide()
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
        alert.messageText = String(localized: "Include Full Safari Page?")
        alert.informativeText = String(localized: """
        This page contains \(pageContext.text.count) characters. Including it may make the response slower.

        Do you want to include it?
        """)
        alert.addButton(withTitle: String(localized: "Include"))
        alert.addButton(withTitle: String(localized: "Do Not Include"))

        if alert.runModal() == .alertFirstButtonReturn {
            DiagnosticLogger.log(
                "User included large Safari page context. characters=\(pageContext.text.count)",
                category: "Safari"
            )
            return screenshot
        }

        let reason = String(localized: "You chose not to include the \(pageContext.text.count)-character Safari page context.")
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
            sourceKind: existingMessage.sourceKind,
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

        var mayPresentAutomationPermission = false
        if !defaults.bool(forKey: Self.hasAnsweredSafariPageCapturePrimerKey) {
            guard presentSafariPageCapturePrimer() else { return screenshot }
            mayPresentAutomationPermission = true
        }

        statusMessage = String(localized: "Reading Safari page...")
        let windowsHiddenForAutomationPrompt = mayPresentAutomationPermission
            ? Self.hideVisibleSasuWindowsForCapture()
            : []
        defer {
            Self.restoreWindows(windowsHiddenForAutomationPrompt)
        }
        do {
            try Task.checkCancellation()
            DiagnosticLogger.log("Attempting Safari page capture. foregroundBundle=\(screenshot.frontmostApplicationBundleIdentifier ?? "unknown") hasVisibleSafariWindow=\(screenshot.hasVisibleSafariWindow)", category: "Safari")
            let pageContext = try safariPageCaptureService.captureCurrentPage()
            try Task.checkCancellation()
            errorMessage = nil
            DiagnosticLogger.log(
                "Safari page capture ready. characters=\(pageContext.text.count)",
                category: "Safari"
            )
            return screenshot.addingBrowserPageContext(pageContext)
        } catch is CancellationError {
            return screenshot
        } catch {
            let issue = error.localizedDescription
            errorMessage = issue
            statusMessage = String(localized: "Screenshot ready, but Safari page content was not included.")
            Self.logger.error("Safari page capture failed: \(issue, privacy: .public)")
            DiagnosticLogger.log("Safari page capture failed: \(issue)", category: "Safari")
            return screenshot.addingBrowserPageCaptureIssue(issue)
        }
    }

    private func presentSafariPageCapturePrimer() -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Safari Enhancement")
        alert.informativeText = String(localized: """
        Sasu can give guidance based on the full Safari page, not just what’s visible.

        When you capture Safari, Sasu can include the active tab title, URL, and page text with your screenshot. It only reads Safari page content when you capture, and sends it with your question.

        macOS may ask whether Sasu can control Safari. Safari may also require Safari > Develop > Developer Settings > Allow JavaScript from Apple Events.
        """)
        alert.addButton(withTitle: String(localized: "Enable for Safari"))
        alert.addButton(withTitle: String(localized: "Not Now"))

        defaults.set(true, forKey: Self.hasAnsweredSafariPageCapturePrimerKey)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            DiagnosticLogger.log("User enabled Safari page capture.", category: "Permissions")
            return true
        default:
            DiagnosticLogger.log("User declined Safari page capture.", category: "Permissions")
            automaticallyIncludeSafariPageContent = false
            statusMessage = String(localized: "Safari page capture is off. You can turn it on in Settings.")
            return false
        }
    }

    private func transcriptContextForRequest() -> String? {
        let messages = transcriptMessages
            .filter { $0.role != .error && $0.role != .screenshot }
            .suffix(10)
            .map { "\($0.role.rawValue): \($0.machineContextText)" }
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

    private func receiveStreamedAnswer(_ partialAnswer: String) {
        streamingResponseText = partialAnswer
        statusMessage = String(localized: "Answering…")
        cursorProgressOverlayController.update(status: String(localized: "Answering…"))
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
            return String(localized: "Add your OpenAI API key in Sasu before capturing the screen.")
        case .missingInviteAccess:
            return String(localized: "Open your Sasu invite link or redeem an invite code in Settings before using invite access.")
        case .invalidBackendURL:
            return String(localized: "Enter a valid Sasu backend URL in Settings.")
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
            return String(localized: "Invite access")
        case .apiKey:
            return String(localized: "My OpenAI API key")
        }
    }
}
