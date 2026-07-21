import Carbon
import Foundation

struct HotkeyConfiguration: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultConfiguration = HotkeyConfiguration(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey | optionKey)
    )

    static let defaultCaptureAndAskConfiguration = HotkeyConfiguration(
        keyCode: UInt32(kVK_ANSI_K),
        modifiers: UInt32(controlKey | optionKey)
    )

    static let defaultTranslateSelectionConfiguration = HotkeyConfiguration(
        keyCode: UInt32(kVK_ANSI_S),
        modifiers: UInt32(controlKey | optionKey)
    )

    static let defaultTranslateAndReplaceConfiguration = HotkeyConfiguration(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: UInt32(controlKey | optionKey)
    )

    static let legacyDefaultTranslateSelectionConfiguration =
        defaultTranslateAndReplaceConfiguration

    static let supportedKeys: [HotkeyKey] = [
        HotkeyKey(name: String(localized: "Space"), keyCode: UInt32(kVK_Space)),
        HotkeyKey(name: String(localized: "Return"), keyCode: UInt32(kVK_Return)),
        HotkeyKey(name: "K", keyCode: UInt32(kVK_ANSI_K)),
        HotkeyKey(name: "J", keyCode: UInt32(kVK_ANSI_J)),
        HotkeyKey(name: "T", keyCode: UInt32(kVK_ANSI_T)),
        HotkeyKey(name: "S", keyCode: UInt32(kVK_ANSI_S)),
        HotkeyKey(name: String(localized: "Slash"), keyCode: UInt32(kVK_ANSI_Slash))
    ]

    var displayName: String {
        let modifierNames = [
            (UInt32(controlKey), String(localized: "Control")),
            (UInt32(optionKey), String(localized: "Option")),
            (UInt32(shiftKey), String(localized: "Shift")),
            (UInt32(cmdKey), String(localized: "Command"))
        ]
            .filter { modifiers & $0.0 != 0 }
            .map { $0.1 }

        return (modifierNames + [Self.keyName(for: keyCode)]).joined(separator: " + ")
    }

    static func keyName(for keyCode: UInt32) -> String {
        supportedKeys.first { $0.keyCode == keyCode }?.name
            ?? String(localized: "Key \(keyCode)")
    }
}

struct HotkeyKey: Identifiable, Equatable {
    var id: UInt32 { keyCode }
    let name: String
    let keyCode: UInt32
}
