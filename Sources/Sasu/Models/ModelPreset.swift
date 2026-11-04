import Foundation

enum AIProvider: String, Equatable {
    case openAI
    case anthropic
}

struct ModelPreset: Identifiable, Equatable {
    let id: String
    let label: String
    let provider: AIProvider
    let modelID: String
    let reasoningEffort: String
    let serviceTier: String
    let imageDetail: String
    /// OpenAI's `ultrafast` service tier is only offered on some models.
    var supportsUltrafast = false

    static let ultrafastServiceTier = "ultrafast"

    static let gpt61SolMediumFast = ModelPreset(
        id: "gpt61SolMediumFast",
        label: String(localized: "Best (GPT-6.1 Sol Medium Fast)"),
        provider: .openAI,
        modelID: "gpt-6.1-sol",
        reasoningEffort: "medium",
        serviceTier: "priority",
        imageDetail: "high",
        supportsUltrafast: true
    )

    static let gpt6AstraMediumFast = ModelPreset(
        id: "gpt6AstraMediumFast",
        label: String(localized: "Better (GPT-6 Astra Medium Fast)"),
        provider: .openAI,
        modelID: "gpt-6-astra",
        reasoningEffort: "medium",
        serviceTier: "priority",
        imageDetail: "high",
        supportsUltrafast: true
    )

    static let gpt56MediumFast = ModelPreset(
        id: "gpt56MediumFast",
        label: String(localized: "Good (GPT-5.6 Medium Fast)"),
        provider: .openAI,
        modelID: "gpt-5.6",
        reasoningEffort: "medium",
        serviceTier: "priority",
        imageDetail: "high"
    )

    static let opus55Best = ModelPreset(
        id: "opus55Best",
        label: String(localized: "Best (Opus 5.5)"),
        provider: .anthropic,
        modelID: "claude-opus-5-5",
        reasoningEffort: "high",
        serviceTier: "auto",
        imageDetail: "high"
    )

    static let fable51Better = ModelPreset(
        id: "fable51Better",
        label: String(localized: "Better (Fable 5.1)"),
        provider: .anthropic,
        modelID: "claude-fable-5-1",
        reasoningEffort: "high",
        serviceTier: "auto",
        imageDetail: "high"
    )

    static let defaultPreset = gpt61SolMediumFast

    static let all: [ModelPreset] = [
        .gpt61SolMediumFast,
        .gpt6AstraMediumFast,
        .gpt56MediumFast,
        .opus55Best,
        .fable51Better
    ]

    static func preset(id: String) -> ModelPreset {
        all.first { $0.id == id } ?? defaultPreset
    }

    static func matching(modelID: String, reasoningEffort: String, serviceTier: String) -> ModelPreset {
        all.first {
            $0.modelID == modelID &&
                $0.reasoningEffort == reasoningEffort &&
                $0.serviceTier == serviceTier
        } ?? all.first { $0.modelID == modelID } ?? defaultPreset
    }

    /// Maps preset IDs saved by earlier versions to their replacements.
    static func replacementID(forRetiredPresetID presetID: String) -> String? {
        switch presetID {
        case "gpt55High", "gpt55HighFast", "gpt56HighFast":
            return gpt61SolMediumFast.id
        case "gpt55MediumFast":
            return gpt56MediumFast.id
        case "opus5Best":
            return opus55Best.id
        default:
            return nil
        }
    }
}
