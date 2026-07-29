import XCTest
@testable import Sasu

final class AnthropicStreamingTests: XCTestCase {
    func testStreamsTextDeltas() async throws {
        let client = makeClient(stream: """
        data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}

        data: {"type":"content_block_delta","delta":{"type":"text_delta","text":" world"}}

        data: {"type":"message_stop"}

        """)

        let result = try await translate(using: client)

        XCTAssertEqual(result, "Hello world")
    }

    func testSurfacesAPIErrorDetails() async {
        let client = makeClient(
            stream: """
            data: {"type":"error","error":{"type":"overloaded_error","message":"Anthropic is overloaded."}}

            """,
            requestID: "req_anthropic_error"
        )

        await XCTAssertThrowsErrorAsync(try await translate(using: client)) { error in
            let description = error.localizedDescription
            XCTAssertTrue(description.contains("overloaded_error"))
            XCTAssertTrue(description.contains("Anthropic is overloaded."))
            XCTAssertTrue(description.contains("req_anthropic_error"))
        }
    }

    func testSurfacesMaxTokensStopReason() async {
        let client = makeClient(
            stream: """
            data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Partial"}}

            data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}

            """,
            requestID: "req_max_tokens"
        )

        await XCTAssertThrowsErrorAsync(try await translate(using: client)) { error in
            let description = error.localizedDescription
            XCTAssertTrue(description.contains("max_tokens"))
            XCTAssertTrue(description.contains("req_max_tokens"))
        }
    }

    private func makeClient(stream: String, requestID: String = "req_test") -> AnthropicClient {
        MockAnthropicURLProtocol.stream = stream
        MockAnthropicURLProtocol.requestID = requestID
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockAnthropicURLProtocol.self]
        return AnthropicClient(session: URLSession(configuration: configuration))
    }

    private func translate(using client: AnthropicClient) async throws -> String {
        try await client.translateClipboardText(
            credential: .anthropicAPIKey("test-key"),
            modelID: "claude-opus-5",
            reasoningEffort: "high",
            sourceText: "テスト",
            conversationContext: nil
        )
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
}

private final class MockAnthropicURLProtocol: URLProtocol {
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
                "request-id": Self.requestID
            ]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.stream.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
