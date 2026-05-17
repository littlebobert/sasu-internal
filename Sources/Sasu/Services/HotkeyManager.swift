import Carbon
import Foundation

final class HotkeyManager {
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let handler: () -> Void
    private let signature = OSType(UInt32(ascii: "SASU"))
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    static func defaultManager(handler: @escaping () -> Void) -> HotkeyManager {
        HotkeyManager(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(controlKey | optionKey),
            handler: handler
        )
    }

    convenience init(configuration: HotkeyConfiguration, handler: @escaping () -> Void) {
        self.init(
            keyCode: configuration.keyCode,
            modifiers: configuration.modifiers,
            handler: handler
        )
    }

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.handler = handler
    }

    func register() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.handler()
                }
                return noErr
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            throw HotkeyError.registrationFailed(installStatus)
        }

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            throw HotkeyError.registrationFailed(registerStatus)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }

        hotKeyRef = nil
        eventHandlerRef = nil
    }

    deinit {
        unregister()
    }
}

enum HotkeyError: LocalizedError {
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            return "Hotkey registration failed with status \(status)."
        }
    }
}

private extension UInt32 {
    init(ascii string: String) {
        self = string.utf8.reduce(0) { partialResult, byte in
            (partialResult << 8) + UInt32(byte)
        }
    }
}
