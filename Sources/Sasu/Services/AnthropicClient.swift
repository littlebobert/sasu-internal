import Foundation
import OSLog

struct AnthropicClient {
    private static let logger = Logger(subsystem: "dev.sasu.Sasu", category: "AnthropicClient")
    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        return URLSession(configuration: configuration)
    }()
    private static let anthropicVersion = "2023-06-01"
    private static let defaultMaxTokens = 16_384

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let session: URLSession

    init(session: URLSession = AnthropicClient.defaultSession) {
        self.session = session
    }

    func askAboutScreenshot(
        credential: AIRequestCredential,
        modelID: String,
        reasoningEffort: String,
        imageDetail: String,
        translationSourceLanguage: TranslationSourceLanguage,
        prompt: String,
        screenshot: ScreenshotPayload,
        conversationContext: String?,
        onPartialAnswer: (@Sendable (String) async -> Void)? = nil
    ) async throws -> AssistantResult {
        let uploadImage = try screenshot.uploadImage
        let promptText = try AIRequestSupport.buildScreenshotPrompt(
            prompt: prompt,
            screenshot: screenshot,
            translationSourceLanguage: translationSourceLanguage,
            conversationContext: conversationContext
        )
        let requestBody = MessagesRequest(
            model: modelID,
            maxTokens: Self.defaultMaxTokens,
            stream: true,
            messages: [
                MessagesMessage(
                    role: "user",
                    content: [
                        .image(mediaType: uploadImage.mimeType, data: uploadImage.data.base64EncodedString()),
                        .text(promptText)
                    ]
                )
            ],
            outputConfig: Self.outputConfig(effort: reasoningEffort)
        )

        let text = try await sendMessagesRequest(
            credential: credential,
            requestBody: requestBody,
            logSummary: "model=\(modelID), effort=\(reasoningEffort), imageDetail=\(imageDetail), uploadBytes=\(uploadImage.data.count), uploadWidth=\(Int(uploadImage.pixelSize.width)), uploadHeight=\(Int(uploadImage.pixelSize.height))",
            onPartialText: { streamedJSON in
                guard let partialAnswer = AIRequestSupport.partialAnswer(from: streamedJSON), !partialAnswer.isEmpty else {
                    return
                }
                await onPartialAnswer?(partialAnswer)
            }
        )

        return AIRequestSupport.parseAssistantResult(from: text)
    }

    func translateClipboardText(
        credential: AIRequestCredential,
        modelID: String,
        reasoningEffort: String,
        sourceText: String,
        translationDirection: TranslationDirection = .forUserInterface,
        conversationContext: String?,
        forSelectionReplacement: Bool = false,
        onPartialAnswer: (@Sendable (String) async -> Void)? = nil
    ) async throws -> String {
        let requestBody = MessagesRequest(
            model: modelID,
            maxTokens: Self.defaultMaxTokens,
            stream: true,
            messages: [
                MessagesMessage(
                    role: "user",
                    content: [
                        .text(AIRequestSupport.buildClipboardTranslationPrompt(
                            sourceText: sourceText,
                            direction: translationDirection,
                            conversationContext: conversationContext,
                            forSelectionReplacement: forSelectionReplacement
                        ))
                    ]
                )
            ],
            outputConfig: Self.outputConfig(effort: reasoningEffort)
        )

        return try await sendMessagesRequest(
            credential: credential,
            requestBody: requestBody,
            logSummary: "model=\(modelID), effort=\(reasoningEffort), sourceCharacters=\(sourceText.count)",
            onPartialText: { text in
                await onPartialAnswer?(text)
            }
        )
    }

    private func sendMessagesRequest(
        credential: AIRequestCredential,
        requestBody: MessagesRequest,
        logSummary: String,
        onPartialText: (@Sendable (String) async -> Void)?
    ) async throws -> String {
        let requestEndpoint: URL
        var headers: [String: String] = [
            "Content-Type": "application/json",
            "anthropic-version": Self.anthropicVersion
        ]
        let destination: String

        switch credential {
        case .anthropicAPIKey(let apiKey):
            requestEndpoint = endpoint
            headers["x-api-key"] = apiKey
            destination = "Anthropic"
        case .backendAccessToken, .openAIAPIKey:
            throw AnthropicError.invalidCredential
        }

        var request = URLRequest(url: requestEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONEncoder().encode(requestBody)
        Self.logger.info("Sending AI request via \(destination, privacy: .public). \(logSummary, privacy: .public), bodyBytes=\(request.httpBody?.count ?? 0)")

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicError.invalidResponse
        }

        let decoder = JSONDecoder()
        if !(200..<300).contains(httpResponse.statusCode) {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
            }
            if let errorResponse = try? decoder.decode(AnthropicErrorResponse.self, from: data) {
                throw AnthropicError.apiError(statusCode: httpResponse.statusCode, message: errorResponse.error.message)
            }
            if let errorResponse = try? decoder.decode(BackendErrorResponse.self, from: data) {
                throw AnthropicError.apiError(statusCode: httpResponse.statusCode, message: errorResponse.detail)
            }

            let bodyPreview = String(data: data, encoding: .utf8)
            throw AnthropicError.httpStatus(httpResponse.statusCode, bodyPreview: bodyPreview)
        }

        let requestID = httpResponse.value(forHTTPHeaderField: "request-id")
            ?? httpResponse.value(forHTTPHeaderField: "x-request-id")
        var text = ""
        var receivedEventCount = 0
        var decodeFailureCount = 0
        var eventTypes: [String: Int] = [:]

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty, payload != "[DONE]", let data = payload.data(using: .utf8) else {
                continue
            }

            let event: MessagesStreamEvent
            do {
                event = try decoder.decode(MessagesStreamEvent.self, from: data)
            } catch {
                decodeFailureCount += 1
                continue
            }

            receivedEventCount += 1
            eventTypes[event.type, default: 0] += 1

            if let terminalError = event.terminalError(statusCode: httpResponse.statusCode, requestID: requestID) {
                Self.logStreamFailure(
                    destination: destination,
                    statusCode: httpResponse.statusCode,
                    requestID: requestID,
                    terminalEvent: event.type,
                    receivedEventCount: receivedEventCount,
                    decodeFailureCount: decodeFailureCount,
                    eventTypes: eventTypes
                )
                throw terminalError
            }

            switch event.type {
            case "content_block_delta":
                if let delta = event.delta?.text, !delta.isEmpty {
                    text += delta
                    await onPartialText?(text)
                }
            case "message_delta":
                if event.delta?.stopReason == "max_tokens" {
                    throw AnthropicError.incompleteResponse(reason: "max_tokens", requestID: requestID)
                }
            default:
                break
            }
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            let eventSummary = Self.eventSummary(eventTypes)
            Self.logStreamFailure(
                destination: destination,
                statusCode: httpResponse.statusCode,
                requestID: requestID,
                terminalEvent: "stream_closed_without_output",
                receivedEventCount: receivedEventCount,
                decodeFailureCount: decodeFailureCount,
                eventTypes: eventTypes
            )
            throw AnthropicError.emptyOutput(requestID: requestID, eventSummary: eventSummary)
        }

        Self.logger.info("AI stream completed. destination=\(destination, privacy: .public), status=\(httpResponse.statusCode), requestID=\(requestID ?? "unknown", privacy: .public), events=\(receivedEventCount), decodeFailures=\(decodeFailureCount), characters=\(text.count)")
        return text
    }

    private static func outputConfig(effort: String) -> OutputConfig? {
        let normalizedEffort = effort.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEffort.isEmpty else { return nil }
        return OutputConfig(effort: normalizedEffort)
    }

    private static func logStreamFailure(
        destination: String,
        statusCode: Int,
        requestID: String?,
        terminalEvent: String,
        receivedEventCount: Int,
        decodeFailureCount: Int,
        eventTypes: [String: Int]
    ) {
        let summary = "AI stream failed. destination=\(destination), status=\(statusCode), requestID=\(requestID ?? "unknown"), terminalEvent=\(terminalEvent), events=\(receivedEventCount), decodeFailures=\(decodeFailureCount), eventTypes=\(eventSummary(eventTypes))"
        logger.error("\(summary, privacy: .public)")
        DiagnosticLogger.log(summary, category: "Anthropic")
    }

    private static func eventSummary(_ eventTypes: [String: Int]) -> String {
        guard !eventTypes.isEmpty else { return "none" }
        return eventTypes.keys.sorted().map { "\($0):\(eventTypes[$0] ?? 0)" }.joined(separator: ",")
    }
}

private struct MessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let stream: Bool
    let messages: [MessagesMessage]
    let outputConfig: OutputConfig?

    private enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case stream
        case messages
        case outputConfig = "output_config"
    }
}

private struct OutputConfig: Encodable {
    let effort: String
}

private struct MessagesMessage: Encodable {
    let role: String
    let content: [MessagesContent]
}

private enum MessagesContent: Encodable {
    case text(String)
    case image(mediaType: String, data: String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let mediaType, let data):
            try container.encode("image", forKey: .type)
            try container.encode(
                MessagesImageSource(type: "base64", mediaType: mediaType, data: data),
                forKey: .source
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
    }
}

private struct MessagesImageSource: Encodable {
    let type: String
    let mediaType: String
    let data: String

    private enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

private struct MessagesStreamEvent: Decodable {
    let type: String
    let delta: MessagesStreamDelta?
    let error: MessagesStreamError?

    func terminalError(statusCode: Int, requestID: String?) -> AnthropicError? {
        switch type {
        case "error":
            return .streamFailed(
                statusCode: statusCode,
                code: error?.type,
                message: error?.message ?? "Anthropic reported an unspecified streaming error.",
                requestID: requestID
            )
        default:
            return nil
        }
    }
}

private struct MessagesStreamDelta: Decodable {
    let type: String?
    let text: String?
    let stopReason: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case stopReason = "stop_reason"
    }
}

private struct MessagesStreamError: Decodable {
    let type: String?
    let message: String
}

private struct AnthropicErrorResponse: Decodable {
    let error: AnthropicErrorDetail
}

private struct AnthropicErrorDetail: Decodable {
    let type: String?
    let message: String
}

enum AnthropicError: LocalizedError {
    case invalidCredential
    case invalidResponse
    case httpStatus(Int, bodyPreview: String?)
    case apiError(statusCode: Int, message: String)
    case streamFailed(statusCode: Int, code: String?, message: String, requestID: String?)
    case incompleteResponse(reason: String, requestID: String?)
    case emptyOutput(requestID: String?, eventSummary: String)

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return String(localized: "Add your Anthropic API key in Sasu before using Claude models.")
        case .invalidResponse:
            return String(localized: "Anthropic returned an invalid response.")
        case .httpStatus(let statusCode, let bodyPreview):
            if statusCode == 429 {
                return String(localized: "Anthropic returned HTTP 429. This is usually a rate limit or quota issue. Try again in a moment.\(Self.formattedBodyPreview(bodyPreview))")
            }
            return String(localized: "Anthropic request failed with HTTP status \(statusCode).\(Self.formattedBodyPreview(bodyPreview))")
        case .apiError(let statusCode, let message):
            if statusCode == 429 {
                return String(localized: "Anthropic returned HTTP 429: \(message)")
            }
            return String(localized: "Anthropic request failed: \(message)")
        case .streamFailed(_, let code, let message, let requestID):
            let codeText = code.map { " [\($0)]" } ?? ""
            return String(localized: "Anthropic's response stream failed\(codeText): \(message)\(Self.formattedRequestID(requestID))")
        case .incompleteResponse(let reason, let requestID):
            return String(localized: "Anthropic stopped before producing a complete answer (\(reason)). Try again.\(Self.formattedRequestID(requestID))")
        case .emptyOutput(let requestID, let eventSummary):
            return String(localized: "Anthropic closed the response stream without returning answer text. Events: \(eventSummary).\(Self.formattedRequestID(requestID))")
        }
    }

    private static func formattedBodyPreview(_ bodyPreview: String?) -> String {
        guard let bodyPreview, !bodyPreview.isEmpty else {
            return ""
        }
        return String(localized: "\n\nResponse body: \(bodyPreview.prefix(500))")
    }

    private static func formattedRequestID(_ requestID: String?) -> String {
        guard let requestID, !requestID.isEmpty else { return "" }
        return String(localized: " Request ID: \(requestID)")
    }
}
