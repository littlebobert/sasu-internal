import Carbon
import Foundation

struct HotkeyConfiguration: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultConfiguration = HotkeyConfiguration(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey | optionKey)
    )

    static let defaultTranslateClipboardConfiguration = HotkeyConfiguration(
        keyCode: UInt32(kVK_ANSI_J),
        modifiers: UInt32(controlKey | optionKey)
    )

    static let defaultTranslateSelectionConfiguration = HotkeyConfiguration(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: UInt32(controlKey | optionKey)
    )

    static let supportedKeys: [HotkeyKey] = [
        HotkeyKey(name: "Space", keyCode: UInt32(kVK_Space)),
        HotkeyKey(name: "Return", keyCode: UInt32(kVK_Return)),
        HotkeyKey(name: "K", keyCode: UInt32(kVK_ANSI_K)),
        HotkeyKey(name: "J", keyCode: UInt32(kVK_ANSI_J)),
        HotkeyKey(name: "T", keyCode: UInt32(kVK_ANSI_T)),
        HotkeyKey(name: "S", keyCode: UInt32(kVK_ANSI_S)),
        HotkeyKey(name: "Slash", keyCode: UInt32(kVK_ANSI_Slash))
    ]

    var displayName: String {
        let modifierNames = [
            (UInt32(controlKey), "Control"),
            (UInt32(optionKey), "Option"),
            (UInt32(shiftKey), "Shift"),
            (UInt32(cmdKey), "Command")
        ]
            .filter { modifiers & $0.0 != 0 }
            .map { $0.1 }

        return (modifierNames + [Self.keyName(for: keyCode)]).joined(separator: " + ")
    }

    static func keyName(for keyCode: UInt32) -> String {
        supportedKeys.first { $0.keyCode == keyCode }?.name ?? "Key \(keyCode)"
    }
}

struct HotkeyKey: Identifiable, Equatable {
    var id: UInt32 { keyCode }
    let name: String
    let keyCode: UInt32
}
