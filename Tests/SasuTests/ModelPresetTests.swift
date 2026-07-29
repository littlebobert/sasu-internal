import XCTest
@testable import Sasu

final class ModelPresetTests: XCTestCase {
    func testBestPresetUsesGPT56HighPriority() {
        let preset = ModelPreset.gpt56HighFast

        XCTAssertEqual(preset.provider, .openAI)
        XCTAssertEqual(preset.modelID, "gpt-5.6")
        XCTAssertEqual(preset.reasoningEffort, "high")
        XCTAssertEqual(preset.serviceTier, "priority")
        XCTAssertEqual(preset.imageDetail, "high")
    }

    func testBetterPresetUsesGPT56MediumPriority() {
        let preset = ModelPreset.gpt56MediumFast

        XCTAssertEqual(preset.provider, .openAI)
        XCTAssertEqual(preset.modelID, "gpt-5.6")
        XCTAssertEqual(preset.reasoningEffort, "medium")
        XCTAssertEqual(preset.serviceTier, "priority")
        XCTAssertEqual(preset.imageDetail, "high")
    }

    func testOpus5BestPresetUsesClaudeOpus5() {
        let preset = ModelPreset.opus5Best

        XCTAssertEqual(preset.provider, .anthropic)
        XCTAssertEqual(preset.modelID, "claude-opus-5")
        XCTAssertEqual(preset.reasoningEffort, "high")
        XCTAssertEqual(preset.serviceTier, "auto")
        XCTAssertEqual(preset.imageDetail, "high")
        XCTAssertTrue(ModelPreset.all.contains(preset))
    }
}
