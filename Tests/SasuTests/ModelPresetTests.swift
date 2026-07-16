import XCTest
@testable import Sasu

final class ModelPresetTests: XCTestCase {
    func testBestPresetUsesGPT56HighPriority() {
        let preset = ModelPreset.gpt56HighFast

        XCTAssertEqual(preset.modelID, "gpt-5.6")
        XCTAssertEqual(preset.reasoningEffort, "high")
        XCTAssertEqual(preset.serviceTier, "priority")
        XCTAssertEqual(preset.imageDetail, "high")
    }

    func testBetterPresetUsesGPT56MediumPriority() {
        let preset = ModelPreset.gpt56MediumFast

        XCTAssertEqual(preset.modelID, "gpt-5.6")
        XCTAssertEqual(preset.reasoningEffort, "medium")
        XCTAssertEqual(preset.serviceTier, "priority")
        XCTAssertEqual(preset.imageDetail, "high")
    }
}
