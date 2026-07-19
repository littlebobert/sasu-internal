import XCTest
@testable import Sasu

final class OpenAIStreamingTests: XCTestCase {
    func testExtractsPartialAnswerBeforeJSONCompletes() {
        let streamedJSON = #"{"answer":"Enter the domain name,\nthen click Next."#

        XCTAssertEqual(
            OpenAIClient.partialAnswer(from: streamedJSON),
            "Enter the domain name,\nthen click Next."
        )
    }

    func testExtractsEscapedQuotesFromPartialAnswer() {
        let streamedJSON = #"{"answer":"Click \"Next\" when ready","actionSuggestion":"#

        XCTAssertEqual(
            OpenAIClient.partialAnswer(from: streamedJSON),
            #"Click "Next" when ready"#
        )
    }

    func testReturnsNilUntilAnswerFieldStarts() {
        XCTAssertNil(OpenAIClient.partialAnswer(from: #"{"#))
        XCTAssertNil(OpenAIClient.partialAnswer(from: #"{"answer":"#))
    }

    func testDecodesUnicodeEscapesFromPartialAnswer() {
        XCTAssertEqual(
            OpenAIClient.partialAnswer(from: #"{"answer":"Click \u6b21\u3078""#),
            "Click 次へ"
        )
    }

    func testRecoversAnswerFromMalformedStructuredResponse() {
        let response = """
        { "answer": "Translated sentence." "actionSuggestion": null }
        """

        XCTAssertEqual(
            OpenAIClient.recoveredAnswer(from: response),
            "Translated sentence."
        )
    }

    func testRecoversAnswerWrappedInSmartQuotes() {
        let response = """
        { “answer”: “Translated sentence.”; “sourceText”: “選択した文章”; “actionSuggestion”: null }
        """

        XCTAssertEqual(
            OpenAIClient.recoveredAnswer(from: response),
            "Translated sentence."
        )
        XCTAssertEqual(
            OpenAIClient.recoveredSourceText(from: response),
            "選択した文章"
        )
    }
}
