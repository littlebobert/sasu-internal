import Foundation
import OSLog

enum AIRequestCredential {
    case openAIAPIKey(String)
    case backendAccessToken(String, baseURL: URL)
}

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
                        .inputText(try buildPrompt(
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
                guard let partialAnswer = Self.partialAnswer(from: streamedJSON), !partialAnswer.isEmpty else {
                    return
                }
                await onPartialAnswer?(partialAnswer)
            }
        )

        return Self.parseAssistantResult(from: text)
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
                        .inputText(buildClipboardTranslationPrompt(
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

        var text = ""
        var receivedEventCount = 0
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
                continue
            }

            receivedEventCount += 1
            if event.type == "response.output_text.delta", let delta = event.delta {
                text += delta
                await onPartialText?(text)
            } else if event.type == "error", let message = event.message {
                throw OpenAIError.apiError(statusCode: httpResponse.statusCode, message: message)
            }
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw OpenAIError.emptyOutput
        }

        Self.logger.info("AI stream completed. destination=\(destination, privacy: .public), status=\(httpResponse.statusCode), events=\(receivedEventCount), characters=\(text.count)")
        return text
    }

    static func partialAnswer(from streamedJSON: String) -> String? {
        partialStringValue(forKey: "answer", from: streamedJSON)
    }

    private static func partialStringValue(
        forKey key: String,
        from streamedJSON: String
    ) -> String? {
        guard let keyRange = streamedJSON.range(of: "\"\(key)\"") else { return nil }
        var index = keyRange.upperBound

        while index < streamedJSON.endIndex, streamedJSON[index].isWhitespace {
            index = streamedJSON.index(after: index)
        }
        guard index < streamedJSON.endIndex, streamedJSON[index] == ":" else { return nil }
        index = streamedJSON.index(after: index)
        while index < streamedJSON.endIndex, streamedJSON[index].isWhitespace {
            index = streamedJSON.index(after: index)
        }
        guard index < streamedJSON.endIndex, streamedJSON[index] == "\"" else { return nil }
        index = streamedJSON.index(after: index)

        var answer = ""
        while index < streamedJSON.endIndex {
            let character = streamedJSON[index]
            if character == "\"" {
                break
            }
            guard character == "\\" else {
                answer.append(character)
                index = streamedJSON.index(after: index)
                continue
            }

            let escapeIndex = streamedJSON.index(after: index)
            guard escapeIndex < streamedJSON.endIndex else { break }
            let escapedCharacter = streamedJSON[escapeIndex]
            switch escapedCharacter {
            case "\"", "\\", "/":
                answer.append(escapedCharacter)
                index = streamedJSON.index(after: escapeIndex)
            case "n":
                answer.append("\n")
                index = streamedJSON.index(after: escapeIndex)
            case "r":
                answer.append("\r")
                index = streamedJSON.index(after: escapeIndex)
            case "t":
                answer.append("\t")
                index = streamedJSON.index(after: escapeIndex)
            case "b":
                answer.append("\u{8}")
                index = streamedJSON.index(after: escapeIndex)
            case "f":
                answer.append("\u{c}")
                index = streamedJSON.index(after: escapeIndex)
            case "u":
                let hexStart = streamedJSON.index(after: escapeIndex)
                guard let (scalar, nextIndex) = Self.unicodeScalar(
                    in: streamedJSON,
                    hexStart: hexStart
                ) else {
                    return answer
                }
                answer.unicodeScalars.append(scalar)
                index = nextIndex
            default:
                index = streamedJSON.index(after: escapeIndex)
            }
        }

        return answer
    }

    static func recoveredAnswer(from structuredText: String) -> String? {
        recoveredStringValue(forKey: "answer", from: structuredText)
    }

    static func recoveredSourceText(from structuredText: String) -> String? {
        recoveredStringValue(forKey: "sourceText", from: structuredText)
    }

    private static func recoveredStringValue(
        forKey key: String,
        from structuredText: String
    ) -> String? {
        let normalizedQuotes = structuredText
            .replacingOccurrences(of: "\u{201c}", with: "\"")
            .replacingOccurrences(of: "\u{201d}", with: "\"")

        guard let value = partialStringValue(forKey: key, from: normalizedQuotes)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }

        return value
    }

    private static func unicodeScalar(
        in text: String,
        hexStart: String.Index
    ) -> (UnicodeScalar, String.Index)? {
        var hexEnd = hexStart
        for _ in 0..<4 {
            guard hexEnd < text.endIndex else { return nil }
            hexEnd = text.index(after: hexEnd)
        }

        guard let value = UInt32(text[hexStart..<hexEnd], radix: 16),
              let scalar = UnicodeScalar(value),
              !(0xD800...0xDFFF).contains(value)
        else {
            return nil
        }
        return (scalar, hexEnd)
    }

    private func buildPrompt(
        prompt: String,
        screenshot: ScreenshotPayload,
        translationSourceLanguage: TranslationSourceLanguage,
        conversationContext: String?
    ) throws -> String {
        let uploadImage = try screenshot.uploadImage
        var parts = [
            "User request:",
            prompt,
            "",
            "Screen context:",
            "- Frontmost app: \(screenshot.frontmostApplicationName ?? "Unknown")",
            "- Frontmost window: \(screenshot.frontmostWindowTitle ?? "Unknown")",
            "- Mouse location: x \(Int(screenshot.mouseLocation.x)), y \(Int(screenshot.mouseLocation.y))",
            "- Cursor marker: the screenshot includes a red crosshair drawn at the pointer location. If the user asks about the cursor, focus on the content under or closest to that red crosshair.",
            "- Original screenshot size: \(Int(screenshot.pixelSize.width)) x \(Int(screenshot.pixelSize.height)) pixels",
            "- Uploaded image size: \(Int(uploadImage.pixelSize.width)) x \(Int(uploadImage.pixelSize.height)) pixels",
            "- Uploaded image format: JPEG, resized for faster requests",
            "",
            """
            Return a JSON object only, with this shape:
            {
              "answer": "Markdown answer for the user",
              "sourceText": "exact visibly selected source text for a selection-translation request, otherwise null",
              "actionSuggestion": {
                "label": "concise, complete instruction for the on-screen callout",
                "exactText": "exact visible text on screen for this target, or null",
                "shape": "rectangle",
                "x": 0,
                "y": 0,
                "width": 100,
                "height": 60,
                "reason": "why this target helps"
              }
            }

            The actionSuggestion is optional. Include it only when the user is asking where to click, what to do next, how to fill something out, or how to navigate a visible UI. Use uploaded image pixel coordinates from the top-left corner. Prefer forgiving rectangles around a target, not tiny click points. If no visual target is useful, set actionSuggestion to null.

            For sourceText, copy only the exact text that is visibly selected or highlighted when the user asks to translate a selection. Preserve its original characters and line breaks. For other requests, set sourceText to null.

            For actionSuggestion.label, give the complete next-step instruction, not merely the highlighted button's name. If the user must type, select, check, upload, or otherwise do something before pressing the highlighted control, include those prerequisite actions in order and end with the control action. For example: `Enter your domain name, then click Next.` Keep it concise enough for a callout, but never omit a required prerequisite just to shorten it.

            For actionSuggestion.exactText, copy the exact visible on-screen text that identifies the target, in the original UI language, such as `ネームサーバー/DNS`. Use null if the target has no visible text (icon-only buttons, toolbar glyphs, etc.). This text is used for local OCR grounding, so do not translate, paraphrase, or describe it. Never put the descriptive label (such as "Back arrow") in exactText.

            For icon-only targets (exactText is null), place the rectangle tightly around the specific icon only. In toolbars with multiple similar icons, use nearby labeled controls as anchors and double-check you selected the correct icon. Prefer shape "circle" for compact icon buttons. Put disambiguation details in reason when needed.

            \(TranslationDirection.screenshotLanguageBehaviorInstructions(
                for: TranslationDirection.preferredUserInterfaceLanguages,
                sourceLanguage: translationSourceLanguage
            ))

            Format the answer field using inline Markdown compatible with the transcript: paragraphs separated by blank lines, emphasis, bold, inline code, and links. Do not use Markdown headings, lists, block quotes, tables, fenced code blocks, thematic rules, or HTML.
            """
        ]

        if let cursorImageLocation = uploadImage.cursorImageLocation {
            parts.insert(
                "- Cursor uploaded-image location: x \(Int(cursorImageLocation.x)), y \(Int(cursorImageLocation.y)) from the uploaded image's top-left corner",
                at: 11
            )
        }

        if let browserPageContext = screenshot.browserPageContext {
            parts.insert(
                contentsOf: [
                    "",
                    "Browser page context:",
                    "- Browser: \(browserPageContext.browserName)",
                    "- Page title: \(browserPageContext.pageTitle.isEmpty ? "Unknown" : browserPageContext.pageTitle)",
                    "- Page URL: \(browserPageContext.pageURL.isEmpty ? "Unknown" : browserPageContext.pageURL)",
                    "- Extracted page text characters: \(browserPageContext.text.count) of \(browserPageContext.originalCharacterCount)\(browserPageContext.isTruncated ? " (truncated)" : "")",
                    "",
                    "Extracted page text:",
                    browserPageContext.text,
                    "",
                    "Use the extracted page text to answer questions about the full Safari page, including content below the visible viewport. Use the screenshot as the source of truth for visible UI, layout, cursor position, and click targets."
                ],
                at: parts.count - 1
            )
        }

        if let conversationContext, !conversationContext.isEmpty {
            parts.insert(
                contentsOf: [
                    "",
                    "Conversation context so far:",
                    conversationContext,
                    "",
                    "Use this context to understand the user's overall goal and prior steps. The attached screenshot is the current screen and should be treated as the source of truth for what is visible now."
                ],
                at: 0
            )
        }

        return parts.joined(separator: "\n")
    }

    private func buildClipboardTranslationPrompt(
        sourceText: String,
        direction: TranslationDirection,
        conversationContext: String?,
        forSelectionReplacement: Bool
    ) -> String {
        var instructions = [
            "- Translate the source text from \(direction.expectedSourceLanguage) into natural \(direction.targetLanguage).",
            "- For mixed-language text, translate the \(direction.expectedSourceLanguage) content into \(direction.targetLanguage) and preserve names or phrases that should remain unchanged.",
            "- Do not return the source text unchanged unless it contains no translatable language.",
            "- Preserve the speaker's tone, intent, names, URLs, emoji, and formatting where helpful."
        ]

        if forSelectionReplacement {
            instructions.append("- Return only the translated text. Do not add labels, explanations, summaries, or Markdown headings.")
        } else {
            instructions.append("- If this appears to be a chat message, include a one-sentence summary only when it adds useful context.")
        }

        instructions.append("- Return inline Markdown only, using paragraphs separated by blank lines, emphasis, bold, inline code, and links. Do not use headings, lists, block quotes, tables, fenced code blocks, thematic rules, or HTML. Do not wrap the answer in JSON.")

        var parts = [
            "Task: translate clipboard text.",
            "",
            "Source text:",
            sourceText,
            "",
            "Instructions:"
        ] + instructions

        if let conversationContext, !conversationContext.isEmpty {
            parts.insert(
                contentsOf: [
                    "Conversation context so far:",
                    conversationContext,
                    "",
                    "Use this only to resolve ambiguous references in the clipboard text.",
                    ""
                ],
                at: 0
            )
        }

        return parts.joined(separator: "\n")
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

    private static func parseAssistantResult(from text: String) -> AssistantResult {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateJSON = jsonCandidate(from: trimmedText)
        let decoder = JSONDecoder()

        if let data = candidateJSON.data(using: .utf8),
           let envelope = try? decoder.decode(AssistantResultEnvelope.self, from: data) {
            return AssistantResult(
                answer: envelope.answer.trimmingCharacters(in: .whitespacesAndNewlines),
                actionSuggestion: envelope.actionSuggestion,
                sourceText: envelope.sourceText?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        if let recoveredAnswer = recoveredAnswer(from: candidateJSON) {
            return AssistantResult(
                answer: recoveredAnswer,
                actionSuggestion: nil,
                sourceText: recoveredSourceText(from: candidateJSON)
            )
        }

        return AssistantResult(answer: trimmedText, actionSuggestion: nil)
    }

    private static func jsonCandidate(from text: String) -> String {
        if text.hasPrefix("```") {
            let lines = text.components(separatedBy: "\n")
            let withoutOpeningFence = lines.dropFirst()
            let withoutClosingFence = withoutOpeningFence.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true
                ? withoutOpeningFence.dropLast()
                : ArraySlice(withoutOpeningFence)
            return withoutClosingFence.joined(separator: "\n")
        }

        return text
    }
}

private struct AssistantResultEnvelope: Decodable {
    let answer: String
    let actionSuggestion: HighlightSuggestion?
    let sourceText: String?
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
    let message: String?
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
    case invalidResponse
    case httpStatus(Int, bodyPreview: String?)
    case apiError(statusCode: Int, message: String)
    case decodingFailed(String, bodyPreview: String?)
    case emptyOutput

    var errorDescription: String? {
        switch self {
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
        case .decodingFailed(let message, let bodyPreview):
            return String(localized: "Sasu could not read OpenAI's response: \(message).\(Self.formattedBodyPreview(bodyPreview))")
        case .emptyOutput:
            return String(localized: "OpenAI returned no answer.")
        }
    }

    private static func formattedBodyPreview(_ bodyPreview: String?) -> String {
        guard let bodyPreview, !bodyPreview.isEmpty else {
            return ""
        }

        return String(localized: "\n\nResponse body: \(bodyPreview.prefix(500))")
    }
}
