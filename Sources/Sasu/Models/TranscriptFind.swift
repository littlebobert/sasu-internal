import Foundation

enum TranscriptFindAction: Equatable {
    case show
    case next
    case previous
}

struct TranscriptFindRequest: Equatable {
    let sequence: Int
    let action: TranscriptFindAction
}

enum TranscriptFindDestination: Hashable {
    case message(UUID)
    case streamingResponse
}

enum TranscriptFindTarget: Hashable {
    case messageText(UUID)
    case sourceLabel(UUID)
    case suggestionLabel(UUID)
    case suggestionReason(UUID)
    case streamingResponse

    var destination: TranscriptFindDestination {
        switch self {
        case let .messageText(id), let .sourceLabel(id), let .suggestionLabel(id), let .suggestionReason(id):
            return .message(id)
        case .streamingResponse:
            return .streamingResponse
        }
    }
}

struct TranscriptFindMatch: Equatable {
    let target: TranscriptFindTarget
    let occurrence: Int

    var destination: TranscriptFindDestination {
        target.destination
    }
}

func transcriptFindMatches(
    query: String,
    messages: [ChatTranscriptMessage],
    streamingResponseText: String
) -> [TranscriptFindMatch] {
    guard !query.isEmpty else { return [] }

    var matches: [TranscriptFindMatch] = []
    for message in messages {
        if let sourceKind = message.sourceKind {
            appendTranscriptFindMatches(
                in: sourceKind.displayLabel,
                query: query,
                target: .sourceLabel(message.id),
                to: &matches
            )
        }
        let messageText = message.sourceKind == nil && message.imageData == nil
            ? transcriptRenderedMarkdownText(message.text)
            : message.text
        appendTranscriptFindMatches(
            in: messageText,
            query: query,
            target: .messageText(message.id),
            to: &matches
        )

        if let suggestion = message.actionSuggestion {
            appendTranscriptFindMatches(
                in: String(localized: "Suggested highlight: \(suggestion.label)"),
                query: query,
                target: .suggestionLabel(message.id),
                to: &matches
            )
            if let reason = suggestion.reason {
                appendTranscriptFindMatches(
                    in: reason,
                    query: query,
                    target: .suggestionReason(message.id),
                    to: &matches
                )
            }
        }
    }

    appendTranscriptFindMatches(
        in: transcriptRenderedMarkdownText(streamingResponseText),
        query: query,
        target: .streamingResponse,
        to: &matches
    )
    return matches
}

func transcriptFindIndex(current: Int, offset: Int, count: Int) -> Int? {
    guard count > 0 else { return nil }
    return ((current + offset) % count + count) % count
}

func transcriptFindRanges(in text: String, query: String) -> [NSRange] {
    guard !query.isEmpty else { return [] }

    var ranges: [NSRange] = []
    var searchRange = text.startIndex..<text.endIndex
    while let range = text.range(
        of: query,
        options: [.caseInsensitive, .diacriticInsensitive],
        range: searchRange,
        locale: .current
    ) {
        ranges.append(NSRange(range, in: text))
        searchRange = range.upperBound..<text.endIndex
    }
    return ranges
}

func transcriptRenderedMarkdownText(_ markdown: String) -> String {
    let normalizedMarkdown = markdown.replacingOccurrences(of: "\r\n", with: "\n")
    guard let attributedString = try? AttributedString(
        markdown: normalizedMarkdown,
        options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) else {
        return normalizedMarkdown
    }
    return String(attributedString.characters)
}

private func appendTranscriptFindMatches(
    in text: String,
    query: String,
    target: TranscriptFindTarget,
    to matches: inout [TranscriptFindMatch]
) {
    for occurrence in transcriptFindRanges(in: text, query: query).indices {
        matches.append(TranscriptFindMatch(target: target, occurrence: occurrence))
    }
}
