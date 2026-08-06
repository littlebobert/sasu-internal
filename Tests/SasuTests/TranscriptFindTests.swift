import XCTest
@testable import Sasu

final class TranscriptFindTests: XCTestCase {
    func testFindMatchesAreCaseAndDiacriticInsensitiveAndOrdered() {
        let firstID = UUID()
        let secondID = UUID()
        let messages = [
            ChatTranscriptMessage(id: firstID, role: .user, text: "Cafe cafe"),
            ChatTranscriptMessage(id: secondID, role: .assistant, text: "CAFÉ")
        ]

        let matches = transcriptFindMatches(
            query: "café",
            messages: messages,
            streamingResponseText: "cafe"
        )

        XCTAssertEqual(matches, [
            TranscriptFindMatch(target: .messageText(firstID), occurrence: 0),
            TranscriptFindMatch(target: .messageText(firstID), occurrence: 1),
            TranscriptFindMatch(target: .messageText(secondID), occurrence: 0),
            TranscriptFindMatch(target: .streamingResponse, occurrence: 0)
        ])
    }

    func testFindIncludesVisibleSuggestionText() {
        let messageID = UUID()
        let suggestion = HighlightSuggestion(
            label: "Continue",
            exactText: nil,
            shape: .rectangle,
            x: 0,
            y: 0,
            width: 1,
            height: 1,
            reason: "Opens the next page"
        )
        let message = ChatTranscriptMessage(
            id: messageID,
            role: .assistant,
            text: "Use the button.",
            actionSuggestion: suggestion
        )

        XCTAssertEqual(
            transcriptFindMatches(query: "next page", messages: [message], streamingResponseText: ""),
            [TranscriptFindMatch(target: .suggestionReason(messageID), occurrence: 0)]
        )
    }

    func testFindUsesRenderedMarkdownText() {
        let messageID = UUID()
        let message = ChatTranscriptMessage(
            id: messageID,
            role: .assistant,
            text: "Use **Continue** next."
        )

        XCTAssertEqual(
            transcriptFindMatches(query: "Continue", messages: [message], streamingResponseText: ""),
            [TranscriptFindMatch(target: .messageText(messageID), occurrence: 0)]
        )
        XCTAssertTrue(
            transcriptFindMatches(query: "**Continue**", messages: [message], streamingResponseText: "").isEmpty
        )
    }

    func testFindRangesIdentifyExactOccurrences() {
        XCTAssertEqual(
            transcriptFindRanges(in: "Cafe café", query: "café"),
            [NSRange(location: 0, length: 4), NSRange(location: 5, length: 4)]
        )
    }

    func testEmptyQueryHasNoMatches() {
        let message = ChatTranscriptMessage(role: .assistant, text: "Answer")
        XCTAssertTrue(
            transcriptFindMatches(query: "", messages: [message], streamingResponseText: "Answer").isEmpty
        )
    }

    func testFindIndexWrapsInBothDirections() {
        XCTAssertEqual(transcriptFindIndex(current: 2, offset: 1, count: 3), 0)
        XCTAssertEqual(transcriptFindIndex(current: 0, offset: -1, count: 3), 2)
        XCTAssertEqual(transcriptFindIndex(current: 0, offset: -4, count: 3), 2)
        XCTAssertNil(transcriptFindIndex(current: 0, offset: 1, count: 0))
    }
}
