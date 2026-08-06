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

struct TranscriptFindMatch: Equatable {
    let destination: TranscriptFindDestination
    let occurrence: Int
}

func transcriptFindMatches(
    query: String,
    messages: [ChatTranscriptMessage],
    streamingResponseText: String
) -> [TranscriptFindMatch] {
    guard !query.isEmpty else { return [] }

    var matches: [TranscriptFindMatch] = []
    for message in messages {
        var searchableText = message.localizedTranscriptText
        if let suggestion = message.actionSuggestion {
            searchableText += "\n\(suggestion.label)"
            if let reason = suggestion.reason {
                searchableText += "\n\(reason)"
            }
        }
        appendTranscriptFindMatches(
            in: searchableText,
            query: query,
            destination: .message(message.id),
            to: &matches
        )
    }

    appendTranscriptFindMatches(
        in: streamingResponseText,
        query: query,
        destination: .streamingResponse,
        to: &matches
    )
    return matches
}

func transcriptFindIndex(current: Int, offset: Int, count: Int) -> Int? {
    guard count > 0 else { return nil }
    return ((current + offset) % count + count) % count
}

private func appendTranscriptFindMatches(
    in text: String,
    query: String,
    destination: TranscriptFindDestination,
    to matches: inout [TranscriptFindMatch]
) {
    var searchRange = text.startIndex..<text.endIndex
    var occurrence = 0

    while let range = text.range(
        of: query,
        options: [.caseInsensitive, .diacriticInsensitive],
        range: searchRange,
        locale: .current
    ) {
        matches.append(TranscriptFindMatch(destination: destination, occurrence: occurrence))
        occurrence += 1
        searchRange = range.upperBound..<text.endIndex
    }
}
