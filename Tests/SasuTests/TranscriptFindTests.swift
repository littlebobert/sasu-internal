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
            TranscriptFindMatch(destination: .message(firstID), occurrence: 0),
            TranscriptFindMatch(destination: .message(firstID), occurrence: 1),
            TranscriptFindMatch(destination: .message(secondID), occurrence: 0),
            TranscriptFindMatch(destination: .streamingResponse, occurrence: 0)
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
            [TranscriptFindMatch(destination: .message(messageID), occurrence: 0)]
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
