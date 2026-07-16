import Foundation

struct ModelPreset: Identifiable, Equatable {
    let id: String
    let label: String
    let modelID: String
    let reasoningEffort: String
    let serviceTier: String
    let imageDetail: String

    static let gpt56HighFast = ModelPreset(
        id: "gpt56HighFast",
        label: "Best (GPT-5.6 High Fast)",
        modelID: "gpt-5.6",
        reasoningEffort: "high",
        serviceTier: "priority",
        imageDetail: "high"
    )

    static let gpt56MediumFast = ModelPreset(
        id: "gpt56MediumFast",
        label: "Better (GPT-5.6 Medium Fast)",
        modelID: "gpt-5.6",
        reasoningEffort: "medium",
        serviceTier: "priority",
        imageDetail: "high"
    )

    static let all: [ModelPreset] = [
        .gpt56HighFast,
        .gpt56MediumFast
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
