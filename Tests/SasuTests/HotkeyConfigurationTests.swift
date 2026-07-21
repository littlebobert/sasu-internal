import Carbon
import XCTest
@testable import Sasu

final class HotkeyConfigurationTests: XCTestCase {
    func testTranslationHotkeysHaveDistinctDefaults() {
        XCTAssertEqual(
            HotkeyConfiguration.defaultTranslateSelectionConfiguration,
            HotkeyConfiguration(
                keyCode: UInt32(kVK_ANSI_S),
                modifiers: UInt32(controlKey | optionKey)
            )
        )
        XCTAssertEqual(
            HotkeyConfiguration.defaultTranslateAndReplaceConfiguration,
            HotkeyConfiguration(
                keyCode: UInt32(kVK_ANSI_T),
                modifiers: UInt32(controlKey | optionKey)
            )
        )
    }

    func testDisplayNamePreservesEveryShortcutComponent() {
        let configuration = HotkeyConfiguration(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )

        let displayName = configuration.displayName
        for component in ["Control", "Option", "Shift", "Command", "Space"] {
            XCTAssertEqual(displayName.components(separatedBy: component).count - 1, 1)
        }
    }

    func testUnknownKeyNamePreservesNumericCode() {
        XCTAssertTrue(HotkeyConfiguration.keyName(for: 999).contains("999"))
    }
}
