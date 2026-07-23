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

    func testUsesCompletedTextWhenNoDeltaWasReceived() async throws {
        let client = makeClient(stream: """
        data: {"type":"response.output_text.done","text":"Completed translation."}

        data: [DONE]

        """)

        let result = try await translate(using: client)

        XCTAssertEqual(result, "Completed translation.")
    }

    func testReturnsRefusalTextWhenNoOutputTextWasReceived() async throws {
        let client = makeClient(stream: """
        data: {"type":"response.refusal.delta","delta":"I can't help with that."}

        data: {"type":"response.refusal.done","refusal":"I can't help with that."}

        data: [DONE]

        """)

        let result = try await translate(using: client)

        XCTAssertEqual(result, "I can't help with that.")
    }

    func testSurfacesFailedResponseDetailsAndRequestID() async {
        let client = makeClient(
            stream: """
            data: {"type":"response.failed","response":{"error":{"code":"server_error","message":"Upstream generation failed."},"incomplete_details":null}}

            data: [DONE]

            """,
            requestID: "req_failed_123"
        )

        await XCTAssertThrowsErrorAsync(try await translate(using: client)) { error in
            let description = error.localizedDescription
            XCTAssertTrue(description.contains("server_error"))
            XCTAssertTrue(description.contains("Upstream generation failed."))
            XCTAssertTrue(description.contains("req_failed_123"))
        }
    }

    func testSurfacesNestedStreamingErrorDetails() async {
        let client = makeClient(
            stream: """
            data: {"type":"error","sequence_number":2,"error":{"type":"invalid_request_error","code":"context_length_exceeded","message":"Your input exceeds the context window of this model.","param":"input"}}

            data: [DONE]

            """,
            requestID: "req_nested_error_123"
        )

        await XCTAssertThrowsErrorAsync(try await translate(using: client)) { error in
            let description = error.localizedDescription
            XCTAssertTrue(description.contains("context_length_exceeded"))
            XCTAssertTrue(description.contains("Your input exceeds the context window"))
            XCTAssertTrue(description.contains("req_nested_error_123"))
        }
    }

    func testSurfacesIncompleteResponseReasonAndRequestID() async {
        let client = makeClient(
            stream: """
            data: {"type":"response.incomplete","response":{"error":null,"incomplete_details":{"reason":"max_output_tokens"}}}

            data: [DONE]

            """,
            requestID: "req_incomplete_123"
        )

        await XCTAssertThrowsErrorAsync(try await translate(using: client)) { error in
            let description = error.localizedDescription
            XCTAssertTrue(description.contains("max_output_tokens"))
            XCTAssertTrue(description.contains("req_incomplete_123"))
        }
    }

    private func makeClient(stream: String, requestID: String = "req_test") -> OpenAIClient {
        MockResponsesURLProtocol.stream = stream
        MockResponsesURLProtocol.requestID = requestID
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockResponsesURLProtocol.self]
        return OpenAIClient(session: URLSession(configuration: configuration))
    }

    private func translate(using client: OpenAIClient) async throws -> String {
        try await client.translateClipboardText(
            credential: .openAIAPIKey("test-key"),
            modelID: "gpt-5.6",
            reasoningEffort: "medium",
            serviceTier: "auto",
            sourceText: "テスト",
            conversationContext: nil
        )
    }
}

private final class MockResponsesURLProtocol: URLProtocol {
    static var stream = ""
    static var requestID = "req_test"

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "text/event-stream",
                "x-request-id": Self.requestID
            ]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.stream.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
