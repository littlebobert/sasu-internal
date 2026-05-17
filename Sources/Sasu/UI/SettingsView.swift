import Carbon
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    hotkeySection
                    apiKeySection
                    modelSection
                    captureSection
                }
                .frame(width: 480, alignment: .leading)
                .padding(20)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        Text("Press \(appModel.hotkeyDescription) to capture your current screen, then type your question.")
            .foregroundStyle(.secondary)
    }

    private var apiKeySection: some View {
        GroupBox("OpenAI API Key") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle()
                        .fill(appModel.hasStoredAPIKey ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(appModel.hasStoredAPIKey ? "API key saved in Keychain" : "No API key saved")
                        .foregroundStyle(.secondary)
                }

                SecureField("sk-...", text: $appModel.apiKeyInput)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save Key") {
                        appModel.saveAPIKey()
                    }
                    .keyboardShortcut(.defaultAction)

                    Button("Delete Key") {
                        appModel.deleteAPIKey()
                    }
                    .disabled(!appModel.hasStoredAPIKey)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var modelSection: some View {
        GroupBox("Model") {
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
        }
    }

    private var hotkeySection: some View {
        GroupBox("Hotkey") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Current: \(appModel.hotkeyDescription)")
                    .foregroundStyle(.secondary)

                Picker("Key", selection: $appModel.hotkeyKeyCode) {
                    ForEach(HotkeyConfiguration.supportedKeys) { key in
                        Text(key.name).tag(key.keyCode)
                    }
                }
                .frame(maxWidth: 240)

                HStack {
                    modifierToggle("Control", UInt32(controlKey))
                    modifierToggle("Option", UInt32(optionKey))
                    modifierToggle("Shift", UInt32(shiftKey))
                    modifierToggle("Command", UInt32(cmdKey))
                }

                HStack {
                    Button("Reset Hotkey") {
                        appModel.resetHotkeyToDefault()
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func modifierToggle(_ title: String, _ modifier: UInt32) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { appModel.hotkeyModifiers & modifier != 0 },
                set: { appModel.setHotkeyModifier(modifier, enabled: $0) }
            )
        )
        .toggleStyle(.checkbox)
    }

    private var captureSection: some View {
        GroupBox("Capture") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Capture Screen") {
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

                if let errorMessage = appModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
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
            }
            .padding(.vertical, 4)
        }
    }
}
