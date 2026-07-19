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
}
