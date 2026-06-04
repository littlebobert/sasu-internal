import Carbon
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @FocusState private var isAPIKeyFieldFocused: Bool
    @State private var hasEditedAPIKey = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hotkeySection
                    accessSection
                    modelSection
                    captureSection
                }
                .frame(width: max(0, geometry.size.width - 48), alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
    }

    private var accessSection: some View {
        GroupBox("Access") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Use", selection: $appModel.accessMode) {
                    ForEach(AccessMode.allCases) { mode in
                        Text(mode.label).tag(mode)
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Backend URL")
                    .font(.caption.bold())
                TextField("https://sasu-backend.herokuapp.com", text: $appModel.backendBaseURLInput)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var inviteAccessStatus: String {
        guard appModel.hasStoredBackendAccessToken else {
            return "No invite access saved"
        }

        if appModel.backendAccessLabel.isEmpty {
            return "Invite access saved in Keychain"
        }

        return "Invite access saved for \(appModel.backendAccessLabel)"
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
                Text(appModel.hasStoredAPIKey ? "API key saved in Keychain" : "No API key saved")
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
        appModel.storedAPIKeyPreview.isEmpty ? "sk-..." : appModel.storedAPIKeyPreview
    }

    private var canSaveAPIKey: Bool {
        let hasKeyInput = !appModel.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasKeyInput && (isAPIKeyFieldFocused || hasEditedAPIKey)
    }

    private var modelSection: some View {
        GroupBox("AI Model") {
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
        GroupBox("Hotkeys") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Capture Screen")
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

                    Button("Reset Capture Hotkey") {
                        appModel.resetHotkeyToDefault()
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Translate Clipboard")
                        .font(.caption.bold())

                    Text("Current: \(appModel.translateClipboardHotkeyDescription)")
                        .foregroundStyle(.secondary)

                    Picker("Key", selection: $appModel.translateClipboardHotkeyKeyCode) {
                        ForEach(HotkeyConfiguration.supportedKeys) { key in
                            Text(key.name).tag(key.keyCode)
                        }
                    }
                    .frame(maxWidth: 240)

                    HStack {
                        modifierToggle("Control", isEnabled: {
                            appModel.translateClipboardHotkeyModifiers & UInt32(controlKey) != 0
                        }, setEnabled: {
                            appModel.setTranslateClipboardHotkeyModifier(UInt32(controlKey), enabled: $0)
                        })
                        modifierToggle("Option", isEnabled: {
                            appModel.translateClipboardHotkeyModifiers & UInt32(optionKey) != 0
                        }, setEnabled: {
                            appModel.setTranslateClipboardHotkeyModifier(UInt32(optionKey), enabled: $0)
                        })
                        modifierToggle("Shift", isEnabled: {
                            appModel.translateClipboardHotkeyModifiers & UInt32(shiftKey) != 0
                        }, setEnabled: {
                            appModel.setTranslateClipboardHotkeyModifier(UInt32(shiftKey), enabled: $0)
                        })
                        modifierToggle("Command", isEnabled: {
                            appModel.translateClipboardHotkeyModifiers & UInt32(cmdKey) != 0
                        }, setEnabled: {
                            appModel.setTranslateClipboardHotkeyModifier(UInt32(cmdKey), enabled: $0)
                        })
                    }

                    Button("Reset Translate Clipboard Hotkey") {
                        appModel.resetTranslateClipboardHotkeyToDefault()
                    }
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modifierToggle(
        _ title: String,
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
        GroupBox("Capture") {
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
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
