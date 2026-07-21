import Carbon
import SwiftUI

struct SettingsView: View {
    private enum SettingsTab: Hashable {
        case general
        case hotkeys
        case ai
        case capture
    }

    @EnvironmentObject private var appModel: AppModel
    @FocusState private var isAPIKeyFieldFocused: Bool
    @State private var hasEditedAPIKey = false
    @State private var selectedTab = SettingsTab.general

    var body: some View {
        TabView(selection: $selectedTab) {
            settingsPage {
                translationSection
                appearanceSection
            }
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            .tag(SettingsTab.general)

            settingsPage {
                hotkeySection
            }
            .tabItem {
                Label("Hotkeys", systemImage: "keyboard")
            }
            .tag(SettingsTab.hotkeys)

            settingsPage {
                accessSection
                modelSection
            }
            .tabItem {
                Label("AI", systemImage: "sparkles")
            }
            .tag(SettingsTab.ai)

            settingsPage {
                captureSection
            }
            .tabItem {
                Label("Capture", systemImage: "camera")
            }
            .tag(SettingsTab.capture)
        }
        .padding(.top, 8)
    }

    private func settingsPage<Content: View>(
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .frame(width: max(0, geometry.size.width - 48), alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.visible)
        }
    }

    private var appearanceSection: some View {
        settingsGroup("Appearance") {
            VStack(alignment: .leading, spacing: 10) {
                Stepper(
                    value: $appModel.transcriptTextSize,
                    in: AppModel.minimumTranscriptTextSize...AppModel.maximumTranscriptTextSize,
                    step: AppModel.transcriptTextSizeStep
                ) {
                    HStack {
                        Text("Transcript text size")

                        Spacer()

                        Text("\(Int(appModel.transcriptTextSize)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: 360)

                Text("You can also use ⌘+ and ⌘−.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var translationSection: some View {
        settingsGroup("Translation") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Translate from", selection: $appModel.translationSourceLanguage) {
                    ForEach(TranslationDirection.availableSourceLanguagesForUserInterface) { sourceLanguage in
                        Text(sourceLanguage.label).tag(sourceLanguage)
                    }
                }
                .frame(maxWidth: 420)

                let direction = TranslationDirection.forUserInterface(
                    sourceLanguage: appModel.translationSourceLanguage
                )
                Text("Reads \(direction.localizedExpectedSourceLanguage) into \(direction.localizedTargetLanguage). Editable selections translate in the reverse direction so you can replace text you are writing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessSection: some View {
        settingsGroup("Access") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Use", selection: $appModel.accessMode) {
                    ForEach(AccessMode.allCases) { mode in
                        Text(accessModeTitle(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                switch appModel.accessMode {
                case .invite:
                    inviteAccessControls
                case .apiKey:
                    apiKeyControls
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accessModeTitle(_ mode: AccessMode) -> LocalizedStringResource {
        switch mode {
        case .invite:
            return "Invite access"
        case .apiKey:
            return "My OpenAI API key"
        }
    }

    private var inviteAccessControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(appModel.hasStoredBackendAccessToken ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(inviteAccessStatus)
                    .foregroundStyle(.secondary)
            }

            SecureField("sasu_inv_...", text: $appModel.inviteCodeInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Redeem Invite") {
                    appModel.redeemInviteCodeFromInput()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canRedeemInvite || appModel.isRequestInFlight)

                Button("Clear Invite Access") {
                    appModel.deleteBackendAccessToken()
                }
                .disabled(!appModel.hasStoredBackendAccessToken)
            }

            Text("Invite links should open Sasu automatically. If they do not, paste the invite code here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Hosted invite access has a monthly usage limit to keep the beta sustainable. Text-only translations use less of the limit than screenshot requests.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        }
    }

    private var inviteAccessStatus: String {
        guard appModel.hasStoredBackendAccessToken else {
            return String(localized: "No invite access saved")
        }

        return String(localized: "Invite access saved in Keychain")
    }

    private var canRedeemInvite: Bool {
        !appModel.inviteCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var apiKeyControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(appModel.hasStoredAPIKey ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(
                    appModel.hasStoredAPIKey
                        ? LocalizedStringResource("API key saved in Keychain")
                        : LocalizedStringResource("No API key saved")
                )
                .foregroundStyle(.secondary)
            }

            SecureField(apiKeyPlaceholder, text: $appModel.apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .focused($isAPIKeyFieldFocused)
                .onChange(of: appModel.apiKeyInput) { newValue in
                    hasEditedAPIKey = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }

            HStack {
                Button("Save Key") {
                    appModel.saveAPIKey()
                    hasEditedAPIKey = !appModel.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSaveAPIKey)

                Button("Clear Key") {
                    appModel.deleteAPIKey()
                    hasEditedAPIKey = false
                }
                .disabled(!appModel.hasStoredAPIKey)
            }
        }
    }

    private var apiKeyPlaceholder: String {
        appModel.storedAPIKeyPreview.isEmpty
            ? String(localized: "sk-...")
            : appModel.storedAPIKeyPreview
    }

    private var canSaveAPIKey: Bool {
        let hasKeyInput = !appModel.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasKeyInput && (isAPIKeyFieldFocused || hasEditedAPIKey)
    }

    private var modelSection: some View {
        settingsGroup("AI Model") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $appModel.selectedModelPresetID) {
                    ForEach(ModelPreset.all) { preset in
                        Text(preset.label).tag(preset.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 360)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hotkeySection: some View {
        settingsGroup("Hotkeys") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sasu Command Wheel")
                        .font(.caption.bold())

                    Text("Current: \(appModel.hotkeyDescription)")
                        .foregroundStyle(.secondary)

                    Picker("Key", selection: $appModel.hotkeyKeyCode) {
                        ForEach(HotkeyConfiguration.supportedKeys) { key in
                            Text(key.name).tag(key.keyCode)
                        }
                    }
                    .frame(maxWidth: 240)

                    HStack {
                        modifierToggle("Control", isEnabled: {
                            appModel.hotkeyModifiers & UInt32(controlKey) != 0
                        }, setEnabled: {
                            appModel.setHotkeyModifier(UInt32(controlKey), enabled: $0)
                        })
                        modifierToggle("Option", isEnabled: {
                            appModel.hotkeyModifiers & UInt32(optionKey) != 0
                        }, setEnabled: {
                            appModel.setHotkeyModifier(UInt32(optionKey), enabled: $0)
                        })
                        modifierToggle("Shift", isEnabled: {
                            appModel.hotkeyModifiers & UInt32(shiftKey) != 0
                        }, setEnabled: {
                            appModel.setHotkeyModifier(UInt32(shiftKey), enabled: $0)
                        })
                        modifierToggle("Command", isEnabled: {
                            appModel.hotkeyModifiers & UInt32(cmdKey) != 0
                        }, setEnabled: {
                            appModel.setHotkeyModifier(UInt32(cmdKey), enabled: $0)
                        })
                    }

                    Button("Reset Command Wheel Hotkey") {
                        appModel.resetHotkeyToDefault()
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Capture & Ask")
                        .font(.caption.bold())

                    Text("Current: \(appModel.captureAndAskHotkeyDescription)")
                        .foregroundStyle(.secondary)

                    Picker("Key", selection: $appModel.captureAndAskHotkeyKeyCode) {
                        ForEach(HotkeyConfiguration.supportedKeys) { key in
                            Text(key.name).tag(key.keyCode)
                        }
                    }
                    .frame(maxWidth: 240)

                    HStack {
                        modifierToggle("Control", isEnabled: {
                            appModel.captureAndAskHotkeyModifiers & UInt32(controlKey) != 0
                        }, setEnabled: {
                            appModel.setCaptureAndAskHotkeyModifier(UInt32(controlKey), enabled: $0)
                        })
                        modifierToggle("Option", isEnabled: {
                            appModel.captureAndAskHotkeyModifiers & UInt32(optionKey) != 0
                        }, setEnabled: {
                            appModel.setCaptureAndAskHotkeyModifier(UInt32(optionKey), enabled: $0)
                        })
                        modifierToggle("Shift", isEnabled: {
                            appModel.captureAndAskHotkeyModifiers & UInt32(shiftKey) != 0
                        }, setEnabled: {
                            appModel.setCaptureAndAskHotkeyModifier(UInt32(shiftKey), enabled: $0)
                        })
                        modifierToggle("Command", isEnabled: {
                            appModel.captureAndAskHotkeyModifiers & UInt32(cmdKey) != 0
                        }, setEnabled: {
                            appModel.setCaptureAndAskHotkeyModifier(UInt32(cmdKey), enabled: $0)
                        })
                    }

                    Button("Reset Capture & Ask Hotkey") {
                        appModel.resetCaptureAndAskHotkeyToDefault()
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Translate Selection")
                        .font(.caption.bold())

                    Text("Select or highlight text, then press the hotkey. With Accessibility access, Sasu reads the selection directly; otherwise it uses a screenshot.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Current: \(appModel.translateSelectionHotkeyDescription)")
                        .foregroundStyle(.secondary)

                    Picker("Key", selection: $appModel.translateSelectionHotkeyKeyCode) {
                        ForEach(HotkeyConfiguration.supportedKeys) { key in
                            Text(key.name).tag(key.keyCode)
                        }
                    }
                    .frame(maxWidth: 240)

                    HStack {
                        modifierToggle("Control", isEnabled: {
                            appModel.translateSelectionHotkeyModifiers & UInt32(controlKey) != 0
                        }, setEnabled: {
                            appModel.setTranslateSelectionHotkeyModifier(UInt32(controlKey), enabled: $0)
                        })
                        modifierToggle("Option", isEnabled: {
                            appModel.translateSelectionHotkeyModifiers & UInt32(optionKey) != 0
                        }, setEnabled: {
                            appModel.setTranslateSelectionHotkeyModifier(UInt32(optionKey), enabled: $0)
                        })
                        modifierToggle("Shift", isEnabled: {
                            appModel.translateSelectionHotkeyModifiers & UInt32(shiftKey) != 0
                        }, setEnabled: {
                            appModel.setTranslateSelectionHotkeyModifier(UInt32(shiftKey), enabled: $0)
                        })
                        modifierToggle("Command", isEnabled: {
                            appModel.translateSelectionHotkeyModifiers & UInt32(cmdKey) != 0
                        }, setEnabled: {
                            appModel.setTranslateSelectionHotkeyModifier(UInt32(cmdKey), enabled: $0)
                        })
                    }

                    Button("Reset Translate Selection Hotkey") {
                        appModel.resetTranslateSelectionHotkeyToDefault()
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Translate & Replace")
                        .font(.caption.bold())

                    Text("Select text in an editable field, then use this command to translate it in the reverse direction and replace it in place. This requires Accessibility permission.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Current: \(appModel.translateAndReplaceHotkeyDescription)")
                        .foregroundStyle(.secondary)

                    Picker("Key", selection: $appModel.translateAndReplaceHotkeyKeyCode) {
                        ForEach(HotkeyConfiguration.supportedKeys) { key in
                            Text(key.name).tag(key.keyCode)
                        }
                    }
                    .frame(maxWidth: 240)

                    HStack {
                        modifierToggle("Control", isEnabled: {
                            appModel.translateAndReplaceHotkeyModifiers & UInt32(controlKey) != 0
                        }, setEnabled: {
                            appModel.setTranslateAndReplaceHotkeyModifier(UInt32(controlKey), enabled: $0)
                        })
                        modifierToggle("Option", isEnabled: {
                            appModel.translateAndReplaceHotkeyModifiers & UInt32(optionKey) != 0
                        }, setEnabled: {
                            appModel.setTranslateAndReplaceHotkeyModifier(UInt32(optionKey), enabled: $0)
                        })
                        modifierToggle("Shift", isEnabled: {
                            appModel.translateAndReplaceHotkeyModifiers & UInt32(shiftKey) != 0
                        }, setEnabled: {
                            appModel.setTranslateAndReplaceHotkeyModifier(UInt32(shiftKey), enabled: $0)
                        })
                        modifierToggle("Command", isEnabled: {
                            appModel.translateAndReplaceHotkeyModifiers & UInt32(cmdKey) != 0
                        }, setEnabled: {
                            appModel.setTranslateAndReplaceHotkeyModifier(UInt32(cmdKey), enabled: $0)
                        })
                    }

                    Button("Reset Translate & Replace Hotkey") {
                        appModel.resetTranslateAndReplaceHotkeyToDefault()
                    }

                    Divider()

                    HStack {
                        Circle()
                            .fill(appModel.hasAccessibilityAccess ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                        Text(
                            appModel.hasAccessibilityAccess
                                ? LocalizedStringResource("Accessibility permission granted")
                                : LocalizedStringResource("Accessibility permission required")
                        )
                        .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("Open Accessibility Settings") {
                            appModel.openAccessibilitySettings()
                        }

                        if !appModel.hasAccessibilityAccess {
                            Button("Request Accessibility Access") {
                                appModel.requestAccessibilityAccess()
                            }
                        }

                        if appModel.shouldOfferAccessibilityRelaunch {
                            Button("Relaunch Sasu") {
                                appModel.relaunchSasu()
                            }
                        }
                    }

                    if appModel.shouldOfferAccessibilityRelaunch {
                        Text("If you enabled Sasu in Accessibility settings, quit and reopen Sasu before Translate & Replace works.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("After enabling Accessibility for Sasu, macOS usually requires quitting and reopening Sasu before Translate & Replace works.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modifierToggle(
        _ title: LocalizedStringResource,
        isEnabled: @escaping () -> Bool,
        setEnabled: @escaping (Bool) -> Void
    ) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: isEnabled,
                set: setEnabled
            )
        )
        .toggleStyle(.checkbox)
    }

    private var captureSection: some View {
        settingsGroup("Capture") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Test Screen Capture") {
                        appModel.captureAndAsk()
                    }
                    .disabled(appModel.isRequestInFlight)

                    if appModel.isRequestInFlight {
                        ProgressView()
                            .controlSize(.small)

                        Button("Stop") {
                            appModel.stopCurrentRequest()
                        }
                    }
                }

                Divider()

                Text("Screen Recording")
                    .font(.caption.bold())

                Text(appModel.statusMessage)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let errorMessage = appModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button("Open Screen Recording Settings") {
                        appModel.openScreenRecordingSettings()
                    }

                    if appModel.shouldOfferPermissionRelaunch {
                        Button("Relaunch Sasu") {
                            appModel.relaunchSasu()
                        }
                    }
                }

                Text("After changing Screen Recording permission, macOS usually requires quitting and reopening Sasu before capture works.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Text("Safari Enhancement")
                    .font(.caption.bold())

                Toggle(
                    "Automatically include full Safari page content",
                    isOn: $appModel.automaticallyIncludeSafariPageContent
                )
                .toggleStyle(.checkbox)

                Text("When Safari is frontmost, Sasu can include the active tab title, URL, and page text with your screenshot so it can explain the whole page. macOS may ask for Automation permission the first time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Open Automation Settings") {
                        appModel.openAutomationSettings()
                    }

                    Text("Safari may also require Safari > Develop > Developer Settings > Allow JavaScript from Apple Events.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsGroup<Content: View>(
        _ title: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            content()
        } label: {
            Text(title)
                .font(.title3.bold())
        }
    }
}
