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

    static let gpt56HighFast = ModelPreset(
        id: "gpt56HighFast",
        label: String(localized: "Best (GPT-5.6 High Fast)"),
        provider: .openAI,
        modelID: "gpt-5.6",
        reasoningEffort: "high",
        serviceTier: "priority",
        imageDetail: "high"
    )

    static let gpt56MediumFast = ModelPreset(
        id: "gpt56MediumFast",
        label: String(localized: "Better (GPT-5.6 Medium Fast)"),
        provider: .openAI,
        modelID: "gpt-5.6",
        reasoningEffort: "medium",
        serviceTier: "priority",
        imageDetail: "high"
    )

    static let opus5Best = ModelPreset(
        id: "opus5Best",
        label: String(localized: "Opus 5 (Best)"),
        provider: .anthropic,
        modelID: "claude-opus-5",
        reasoningEffort: "high",
        serviceTier: "auto",
        imageDetail: "high"
    )

    static let all: [ModelPreset] = [
        .gpt56HighFast,
        .gpt56MediumFast,
        .opus5Best
    ]

    static func preset(id: String) -> ModelPreset {
        all.first { $0.id == id } ?? .gpt56HighFast
    }

    static func matching(modelID: String, reasoningEffort: String, serviceTier: String) -> ModelPreset {
        all.first {
            $0.modelID == modelID &&
                $0.reasoningEffort == reasoningEffort &&
                $0.serviceTier == serviceTier
        } ?? all.first { $0.modelID == modelID } ?? .gpt56HighFast
    }
}
