import CoreGraphics
import Foundation
import Vision

struct HighlightGroundingService {
    func groundedSuggestion(
        _ suggestion: HighlightSuggestion,
        in screenshot: ScreenshotPayload
    ) async -> HighlightSuggestion {
        let targetText = (suggestion.exactText ?? suggestion.label)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetText.isEmpty else { return suggestion }

        do {
            let uploadImage = try screenshot.uploadImage
            let observations = try await recognizedText(in: screenshot)
            guard let match = bestMatch(
                targetText: targetText,
                roughRect: CGRect(
                    x: suggestion.x,
                    y: suggestion.y,
                    width: suggestion.width,
                    height: suggestion.height
                ),
                observations: observations,
                originalSize: screenshot.pixelSize,
                scaleToUpload: uploadImage.scaleFromOriginal
            ) else {
                return suggestion
            }

            return suggestion.replacingRect(match)
        } catch {
            return suggestion
        }
    }

    private func recognizedText(in screenshot: ScreenshotPayload) async throws -> [TextObservation] {
        let pngData = screenshot.pngData
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(data: pngData)
            try handler.perform([request])

            return (request.results ?? []).flatMap { observation -> [TextObservation] in
                observation.topCandidates(3).map {
                    TextObservation(text: $0.string, boundingBox: observation.boundingBox)
                }
            }
        }.value
    }

    private func bestMatch(
        targetText: String,
        roughRect: CGRect,
        observations: [TextObservation],
        originalSize: CGSize,
        scaleToUpload: CGFloat
    ) -> CGRect? {
        let normalizedTarget = normalized(targetText)
        guard !normalizedTarget.isEmpty else { return nil }

        let scoredMatches = observations.compactMap { observation -> ScoredRect? in
            let normalizedObservation = normalized(observation.text)
            guard !normalizedObservation.isEmpty else { return nil }

            let textScore = score(target: normalizedTarget, candidate: normalizedObservation)
            guard textScore >= 0.72 else { return nil }

            let uploadRect = uploadRect(
                from: observation.boundingBox,
                originalSize: originalSize,
                scaleToUpload: scaleToUpload
            )
            let distanceScore = distanceScore(from: uploadRect, to: roughRect)

            return ScoredRect(
                rect: paddedRect(uploadRect),
                score: textScore + distanceScore
            )
        }

        return scoredMatches.max { $0.score < $1.score }?.rect
    }

    private func uploadRect(
        from normalizedRect: CGRect,
        originalSize: CGSize,
        scaleToUpload: CGFloat
    ) -> CGRect {
        let originalRect = CGRect(
            x: normalizedRect.minX * originalSize.width,
            y: (1 - normalizedRect.maxY) * originalSize.height,
            width: normalizedRect.width * originalSize.width,
            height: normalizedRect.height * originalSize.height
        )

        return CGRect(
            x: originalRect.minX * scaleToUpload,
            y: originalRect.minY * scaleToUpload,
            width: originalRect.width * scaleToUpload,
            height: originalRect.height * scaleToUpload
        )
    }

    private func paddedRect(_ rect: CGRect) -> CGRect {
        rect
            .insetBy(dx: -14, dy: -8)
            .standardized
    }

    private func distanceScore(from candidate: CGRect, to roughRect: CGRect) -> CGFloat {
        let dx = candidate.midX - roughRect.midX
        let dy = candidate.midY - roughRect.midY
        let distance = sqrt(dx * dx + dy * dy)
        return max(0, 0.2 - min(distance / 2000, 0.2))
    }

    private func score(target: String, candidate: String) -> CGFloat {
        if target == candidate {
            return 1
        }

        if candidate.contains(target) || target.contains(candidate) {
            return 0.9
        }

        let distance = levenshteinDistance(target, candidate)
        let longest = max(target.count, candidate.count)
        guard longest > 0 else { return 0 }

        return max(0, 1 - CGFloat(distance) / CGFloat(longest))
    }

    private func normalized(_ string: String) -> String {
        string
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .filter { !$0.isWhitespace && !$0.isNewline }
    }

    private func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let lhs = Array(lhs)
        let rhs = Array(rhs)
        var distances = Array(0...rhs.count)

        for (lhsIndex, lhsCharacter) in lhs.enumerated() {
            var previous = lhsIndex
            distances[0] = lhsIndex + 1

            for (rhsIndex, rhsCharacter) in rhs.enumerated() {
                let oldDistance = distances[rhsIndex + 1]
                distances[rhsIndex + 1] = min(
                    distances[rhsIndex + 1] + 1,
                    distances[rhsIndex] + 1,
                    previous + (lhsCharacter == rhsCharacter ? 0 : 1)
                )
                previous = oldDistance
            }
        }

        return distances[rhs.count]
    }
}

private struct TextObservation {
    let text: String
    let boundingBox: CGRect
}

private struct ScoredRect {
    let rect: CGRect
    let score: CGFloat
}
