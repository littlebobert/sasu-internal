import Foundation
import OSLog

struct OpenAIClient {
    private static let logger = Logger(subsystem: "dev.sasu.Sasu", category: "OpenAIClient")
    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        return URLSession(configuration: configuration)
    }()

    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    private let session: URLSession

    init(session: URLSession = OpenAIClient.defaultSession) {
        self.session = session
    }

    func askAboutScreenshot(
        credential: AIRequestCredential,
        modelID: String,
        reasoningEffort: String,
        serviceTier: String,
        imageDetail: String,
        translationSourceLanguage: TranslationSourceLanguage,
        prompt: String,
        screenshot: ScreenshotPayload,
        conversationContext: String?,
        onPartialAnswer: (@Sendable (String) async -> Void)? = nil
    ) async throws -> AssistantResult {
        let uploadImage = try screenshot.uploadImage
        let requestBody = ResponsesRequest(
            model: modelID,
            input: [
                ResponsesInput(
                    role: "user",
                    content: [
                        .inputText(try AIRequestSupport.buildScreenshotPrompt(
                            prompt: prompt,
                            screenshot: screenshot,
                            translationSourceLanguage: translationSourceLanguage,
                            conversationContext: conversationContext
                        )),
                        .inputImage(
                            imageURL: uploadImage.base64DataURL,
                            detail: imageDetail
                        )
                    ]
                )
            ],
            reasoning: Self.reasoningConfiguration(modelID: modelID, effort: reasoningEffort),
            serviceTier: Self.serviceTierParameter(serviceTier),
            stream: true
        )

        let text = try await sendResponsesRequest(
            credential: credential,
            requestBody: requestBody,
            logSummary: "model=\(modelID), reasoning=\(reasoningEffort), serviceTier=\(serviceTier), imageDetail=\(imageDetail), uploadBytes=\(uploadImage.data.count), uploadWidth=\(Int(uploadImage.pixelSize.width)), uploadHeight=\(Int(uploadImage.pixelSize.height))",
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
        serviceTier: String,
        sourceText: String,
        translationDirection: TranslationDirection = .forUserInterface,
        conversationContext: String?,
        forSelectionReplacement: Bool = false,
        onPartialAnswer: (@Sendable (String) async -> Void)? = nil
    ) async throws -> String {
        let requestBody = ResponsesRequest(
            model: modelID,
            input: [
                ResponsesInput(
                    role: "user",
                    content: [
                        .inputText(AIRequestSupport.buildClipboardTranslationPrompt(
                            sourceText: sourceText,
                            direction: translationDirection,
                            conversationContext: conversationContext,
                            forSelectionReplacement: forSelectionReplacement
                        ))
                    ]
                )
            ],
            reasoning: Self.reasoningConfiguration(modelID: modelID, effort: reasoningEffort),
            serviceTier: Self.serviceTierParameter(serviceTier),
            stream: true
        )

        return try await sendResponsesRequest(
            credential: credential,
            requestBody: requestBody,
            logSummary: "model=\(modelID), reasoning=\(reasoningEffort), serviceTier=\(serviceTier), sourceCharacters=\(sourceText.count)",
            onPartialText: { text in
                await onPartialAnswer?(text)
            }
        )
    }

    private func sendResponsesRequest(
        credential: AIRequestCredential,
        requestBody: ResponsesRequest,
        logSummary: String,
        onPartialText: (@Sendable (String) async -> Void)?
    ) async throws -> String {
        let requestEndpoint: URL
        let authorizationHeader: String
        let destination: String
        switch credential {
        case .openAIAPIKey(let apiKey):
            requestEndpoint = endpoint
            authorizationHeader = "Bearer \(apiKey)"
            destination = "OpenAI"
        case .backendAccessToken(let accessToken, let baseURL):
            requestEndpoint = baseURL.appendingPathComponent("v1/responses")
            authorizationHeader = "Bearer \(accessToken)"
            destination = "Sasu backend"
        case .anthropicAPIKey:
            throw OpenAIError.invalidCredential
        }

        var request = URLRequest(url: requestEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        Self.logger.info("Sending AI request via \(destination, privacy: .public). \(logSummary, privacy: .public), bodyBytes=\(request.httpBody?.count ?? 0)")

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }

        let decoder = JSONDecoder()
        if !(200..<300).contains(httpResponse.statusCode) {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
            }
            if let errorResponse = try? decoder.decode(OpenAIErrorResponse.self, from: data) {
                throw OpenAIError.apiError(statusCode: httpResponse.statusCode, message: errorResponse.error.message)
            }
            if let errorResponse = try? decoder.decode(BackendErrorResponse.self, from: data) {
                throw OpenAIError.apiError(statusCode: httpResponse.statusCode, message: errorResponse.detail)
            }

            let bodyPreview = String(data: data, encoding: .utf8)
            throw OpenAIError.httpStatus(httpResponse.statusCode, bodyPreview: bodyPreview)
        }

        let requestID = httpResponse.value(forHTTPHeaderField: "x-request-id")
        var text = ""
        var refusalText = ""
        var completedText: String?
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

            let event: ResponsesStreamEvent
            do {
                event = try decoder.decode(ResponsesStreamEvent.self, from: data)
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
            case "response.output_text.delta":
                if let delta = event.delta {
                    text += delta
                    await onPartialText?(text)
                }
            case "response.output_text.done":
                completedText = event.text
            case "response.refusal.delta":
                if let delta = event.delta {
                    refusalText += delta
                    await onPartialText?(refusalText)
                }
            case "response.refusal.done":
                if refusalText.isEmpty, let refusal = event.refusal {
                    refusalText = refusal
                }
            default:
                break
            }
        }

        if text.isEmpty, let completedText {
            text = completedText
        }
        if text.isEmpty {
            text = refusalText
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
            throw OpenAIError.emptyOutput(requestID: requestID, eventSummary: eventSummary)
        }

        Self.logger.info("AI stream completed. destination=\(destination, privacy: .public), status=\(httpResponse.statusCode), requestID=\(requestID ?? "unknown", privacy: .public), events=\(receivedEventCount), decodeFailures=\(decodeFailureCount), characters=\(text.count)")
        return text
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
        DiagnosticLogger.log(summary, category: "OpenAI")
    }

    private static func eventSummary(_ eventTypes: [String: Int]) -> String {
        guard !eventTypes.isEmpty else { return "none" }
        return eventTypes.keys.sorted().map { "\($0):\(eventTypes[$0] ?? 0)" }.joined(separator: ",")
    }

    private static func reasoningConfiguration(modelID: String, effort: String) -> ReasoningConfiguration? {
        let normalizedModelID = modelID.lowercased()
        let normalizedEffort = effort.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEffort.isEmpty else { return nil }
        guard normalizedModelID.hasPrefix("gpt-5") || normalizedModelID.hasPrefix("o") else {
            return nil
        }

        return ReasoningConfiguration(effort: normalizedEffort)
    }

    private static func serviceTierParameter(_ serviceTier: String) -> String? {
        let normalizedServiceTier = serviceTier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedServiceTier.isEmpty, normalizedServiceTier != "auto" else {
            return nil
        }

        return normalizedServiceTier
    }
}

private struct ResponsesRequest: Encodable {
    let model: String
    let input: [ResponsesInput]
    let reasoning: ReasoningConfiguration?
    let serviceTier: String?
    let stream: Bool

    private enum CodingKeys: String, CodingKey {
        case model
        case input
        case reasoning
        case serviceTier = "service_tier"
        case stream
    }
}

private struct ResponsesStreamEvent: Decodable {
    let type: String
    let delta: String?
    let text: String?
    let refusal: String?
    let message: String?
    let code: String?
    let error: StreamErrorDetail?
    let response: StreamResponse?

    func terminalError(statusCode: Int, requestID: String?) -> OpenAIError? {
        switch type {
        case "error":
            return .streamFailed(
                statusCode: statusCode,
                code: code ?? error?.code,
                message: message ?? error?.message ?? "OpenAI reported an unspecified streaming error.",
                requestID: requestID
            )
        case "response.failed":
            return .streamFailed(
                statusCode: statusCode,
                code: response?.error?.code,
                message: response?.error?.message ?? "OpenAI reported that the response failed.",
                requestID: requestID
            )
        case "response.incomplete":
            return .incompleteResponse(
                reason: response?.incompleteDetails?.reason ?? "unknown",
                requestID: requestID
            )
        default:
            return nil
        }
    }
}

private struct StreamResponse: Decodable {
    let error: StreamErrorDetail?
    let incompleteDetails: StreamIncompleteDetails?

    private enum CodingKeys: String, CodingKey {
        case error
        case incompleteDetails = "incomplete_details"
    }
}

private struct StreamErrorDetail: Decodable {
    let code: String?
    let message: String
}

private struct StreamIncompleteDetails: Decodable {
    let reason: String?
}

private struct ReasoningConfiguration: Encodable {
    let effort: String
}

private struct ResponsesInput: Encodable {
    let role: String
    let content: [ResponsesContent]
}

private enum ResponsesContent: Encodable {
    case inputText(String)
    case inputImage(imageURL: String, detail: String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .inputText(let text):
            try container.encode("input_text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .inputImage(let imageURL, let detail):
            try container.encode("input_image", forKey: .type)
            try container.encode(imageURL, forKey: .imageURL)
            if !detail.isEmpty {
                try container.encode(detail, forKey: .detail)
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
        case detail
    }
}

private struct ResponsesResponse: Decodable {
    let outputText: String?
    let outputItems: [ResponsesOutput]

    private enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.outputText = try container.decodeIfPresent(String.self, forKey: .outputText)
        self.outputItems = try container.decodeIfPresent([ResponsesOutput].self, forKey: .output) ?? []
    }
}

private struct ResponsesOutput: Decodable {
    let content: [ResponsesOutputContent]

    private enum CodingKeys: String, CodingKey {
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.content = try container.decodeIfPresent([ResponsesOutputContent].self, forKey: .content) ?? []
    }
}

private struct ResponsesOutputContent: Decodable {
    let text: String?
}

private struct OpenAIErrorResponse: Decodable {
    let error: OpenAIErrorDetail
}

private struct OpenAIErrorDetail: Decodable {
    let message: String
}

enum OpenAIError: LocalizedError {
    case invalidCredential
    case invalidResponse
    case httpStatus(Int, bodyPreview: String?)
    case apiError(statusCode: Int, message: String)
    case streamFailed(statusCode: Int, code: String?, message: String, requestID: String?)
    case incompleteResponse(reason: String, requestID: String?)
    case decodingFailed(String, bodyPreview: String?)
    case emptyOutput(requestID: String?, eventSummary: String)

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return String(localized: "Add your OpenAI API key in Sasu before using OpenAI models.")
        case .invalidResponse:
            return String(localized: "OpenAI returned an invalid response.")
        case .httpStatus(let statusCode, let bodyPreview):
            if statusCode == 429 {
                return String(localized: "OpenAI returned HTTP 429. This is usually a rate limit, quota issue, or unsupported priority processing. Set Speed to auto and try again.\(Self.formattedBodyPreview(bodyPreview))")
            }

            return String(localized: "OpenAI request failed with HTTP status \(statusCode).\(Self.formattedBodyPreview(bodyPreview))")
        case .apiError(let statusCode, let message):
            if statusCode == 429 {
                return String(localized: "OpenAI returned HTTP 429: \(message) Set Speed to auto if it is currently priority.")
            }

            return String(localized: "OpenAI request failed: \(message)")
        case .streamFailed(_, let code, let message, let requestID):
            let codeText = code.map { " [\($0)]" } ?? ""
            return String(localized: "OpenAI's response stream failed\(codeText): \(message)\(Self.formattedRequestID(requestID))")
        case .incompleteResponse(let reason, let requestID):
            return String(localized: "OpenAI stopped before producing a complete answer (\(reason)). Try again, or lower Reasoning if this continues.\(Self.formattedRequestID(requestID))")
        case .decodingFailed(let message, let bodyPreview):
            return String(localized: "Sasu could not read OpenAI's response: \(message).\(Self.formattedBodyPreview(bodyPreview))")
        case .emptyOutput(let requestID, let eventSummary):
            return String(localized: "OpenAI closed the response stream without returning answer text. Events: \(eventSummary).\(Self.formattedRequestID(requestID))")
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
