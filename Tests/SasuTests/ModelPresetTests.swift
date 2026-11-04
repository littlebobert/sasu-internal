import XCTest
@testable import Sasu

final class ModelPresetTests: XCTestCase {
    func testOpenAIPresetsAreSolAstraAnd56AtMediumPriority() {
        let openAIPresets = ModelPreset.all.filter { $0.provider == .openAI }

        XCTAssertEqual(openAIPresets.map(\.modelID), ["gpt-6.1-sol", "gpt-6-astra", "gpt-5.6"])
        for preset in openAIPresets {
            XCTAssertEqual(preset.reasoningEffort, "medium", preset.id)
            XCTAssertEqual(preset.serviceTier, "priority", preset.id)
            XCTAssertEqual(preset.imageDetail, "high", preset.id)
        }
    }

    func testUltrafastIsOfferedOnlyOnSolAndAstra() {
        XCTAssertTrue(ModelPreset.gpt61SolMediumFast.supportsUltrafast)
        XCTAssertTrue(ModelPreset.gpt6AstraMediumFast.supportsUltrafast)
        XCTAssertFalse(ModelPreset.gpt56MediumFast.supportsUltrafast)
        XCTAssertFalse(ModelPreset.opus55Best.supportsUltrafast)
        XCTAssertFalse(ModelPreset.fable51Better.supportsUltrafast)
    }

    func testAnthropicPresetsAreOpus55ThenFable51() {
        let anthropicPresets = ModelPreset.all.filter { $0.provider == .anthropic }

        XCTAssertEqual(anthropicPresets.map(\.modelID), ["claude-opus-5-5", "claude-fable-5-1"])
        for preset in anthropicPresets {
            XCTAssertEqual(preset.serviceTier, "auto", preset.id)
        }
    }

    func testDefaultPresetIsBestOpenAI() {
        XCTAssertEqual(ModelPreset.defaultPreset, .gpt61SolMediumFast)
        XCTAssertEqual(ModelPreset.preset(id: "unknown"), .gpt61SolMediumFast)
    }

    func testRetiredPresetIDsMoveToTheirReplacements() {
        XCTAssertEqual(ModelPreset.replacementID(forRetiredPresetID: "gpt56HighFast"), ModelPreset.gpt61SolMediumFast.id)
        XCTAssertEqual(ModelPreset.replacementID(forRetiredPresetID: "gpt55HighFast"), ModelPreset.gpt61SolMediumFast.id)
        XCTAssertEqual(ModelPreset.replacementID(forRetiredPresetID: "gpt55MediumFast"), ModelPreset.gpt56MediumFast.id)
        XCTAssertEqual(ModelPreset.replacementID(forRetiredPresetID: "opus5Best"), ModelPreset.opus55Best.id)
        XCTAssertNil(ModelPreset.replacementID(forRetiredPresetID: ModelPreset.gpt56MediumFast.id))
    }
}
