import Foundation

struct ModelPreset: Identifiable, Equatable {
    let id: String
    let label: String
    let modelID: String
    let reasoningEffort: String
    let serviceTier: String
    let imageDetail: String

    static let gpt55HighFast = ModelPreset(
        id: "gpt55HighFast",
        label: "Best (GPT-5.5 High Fast)",
        modelID: "gpt-5.5",
        reasoningEffort: "high",
        serviceTier: "priority",
        imageDetail: "high"
    )

    static let gpt55MediumFast = ModelPreset(
        id: "gpt55MediumFast",
        label: "Better (GPT-5.5 Medium Fast)",
        modelID: "gpt-5.5",
        reasoningEffort: "medium",
        serviceTier: "priority",
        imageDetail: "high"
    )

    static let all: [ModelPreset] = [
        .gpt55HighFast,
        .gpt55MediumFast
    ]

    static func preset(id: String) -> ModelPreset {
        all.first { $0.id == id } ?? .gpt55HighFast
    }

    static func matching(modelID: String, reasoningEffort: String, serviceTier: String) -> ModelPreset {
        all.first {
            $0.modelID == modelID &&
                $0.reasoningEffort == reasoningEffort &&
                $0.serviceTier == serviceTier
        } ?? all.first { $0.modelID == modelID } ?? .gpt55HighFast
    }
}
