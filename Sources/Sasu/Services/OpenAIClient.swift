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
        prompt: String,
        screenshot: ScreenshotPayload,
        conversationContext: String?
    ) async throws -> AssistantResult {
        let uploadImage = try screenshot.uploadImage
        let requestBody = ResponsesRequest(
            model: modelID,
            input: [
                ResponsesInput(
                    role: "user",
                    content: [
                        .inputText(try buildPrompt(prompt: prompt, screenshot: screenshot, conversationContext: conversationContext)),
                        .inputImage(
                            imageURL: uploadImage.base64DataURL,
                            detail: imageDetail
                        )
                    ]
                )
            ],
            reasoning: Self.reasoningConfiguration(modelID: modelID, effort: reasoningEffort),
            serviceTier: Self.serviceTierParameter(serviceTier)
        )

        let text = try await sendResponsesRequest(
            credential: credential,
            requestBody: requestBody,
            logSummary: "model=\(modelID), reasoning=\(reasoningEffort), serviceTier=\(serviceTier), imageDetail=\(imageDetail), uploadBytes=\(uploadImage.data.count), uploadWidth=\(Int(uploadImage.pixelSize.width)), uploadHeight=\(Int(uploadImage.pixelSize.height))"
        )

        return Self.parseAssistantResult(from: text)
    }

    func translateClipboardText(
        credential: AIRequestCredential,
        modelID: String,
        reasoningEffort: String,
        serviceTier: String,
        sourceText: String,
        conversationContext: String?,
        forSelectionReplacement: Bool = false
    ) async throws -> String {
        let requestBody = ResponsesRequest(
            model: modelID,
            input: [
                ResponsesInput(
                    role: "user",
                    content: [
                        .inputText(buildClipboardTranslationPrompt(
                            sourceText: sourceText,
                            conversationContext: conversationContext,
                            forSelectionReplacement: forSelectionReplacement
                        ))
                    ]
                )
            ],
            reasoning: Self.reasoningConfiguration(modelID: modelID, effort: reasoningEffort),
            serviceTier: Self.serviceTierParameter(serviceTier)
        )

        return try await sendResponsesRequest(
            credential: credential,
            requestBody: requestBody,
            logSummary: "model=\(modelID), reasoning=\(reasoningEffort), serviceTier=\(serviceTier), sourceCharacters=\(sourceText.count)"
        )
    }

    private func sendResponsesRequest(
        credential: AIRequestCredential,
        requestBody: ResponsesRequest,
        logSummary: String
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

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        Self.logger.info("AI response received. destination=\(destination, privacy: .public), status=\(httpResponse.statusCode), bytes=\(data.count)")

        let decoder = JSONDecoder()
        if !(200..<300).contains(httpResponse.statusCode) {
            if let errorResponse = try? decoder.decode(OpenAIErrorResponse.self, from: data) {
                throw OpenAIError.apiError(statusCode: httpResponse.statusCode, message: errorResponse.error.message)
            }
            if let errorResponse = try? decoder.decode(BackendErrorResponse.self, from: data) {
                throw OpenAIError.apiError(statusCode: httpResponse.statusCode, message: errorResponse.detail)
            }

            let bodyPreview = String(data: data, encoding: .utf8)
            throw OpenAIError.httpStatus(httpResponse.statusCode, bodyPreview: bodyPreview)
        }

        let responseBody: ResponsesResponse
        do {
            responseBody = try decoder.decode(ResponsesResponse.self, from: data)
        } catch {
            let bodyPreview = String(data: data, encoding: .utf8)
            Self.logger.error("Could not decode OpenAI response: \(error.localizedDescription, privacy: .public)")
            throw OpenAIError.decodingFailed(error.localizedDescription, bodyPreview: bodyPreview)
        }

        let outputText = responseBody.outputText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let collectedText = responseBody.outputItems
            .flatMap(\.content)
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let text = outputText?.isEmpty == false ? outputText! : collectedText

        guard !text.isEmpty else {
            throw OpenAIError.emptyOutput
        }

        return text
    }

    private func buildPrompt(prompt: String, screenshot: ScreenshotPayload, conversationContext: String?) throws -> String {
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
              "actionSuggestion": {
                "label": "short target label",
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

            For actionSuggestion.exactText, copy the exact visible on-screen text that identifies the target, in the original UI language, such as `ネームサーバー/DNS`. Use null if the target has no visible text (icon-only buttons, toolbar glyphs, etc.). This text is used for local OCR grounding, so do not translate, paraphrase, or describe it. Never put the descriptive label (such as "Back arrow") in exactText.

            For icon-only targets (exactText is null), place the rectangle tightly around the specific icon only. In toolbars with multiple similar icons, use nearby labeled controls as anchors and double-check you selected the correct icon. Prefer shape "circle" for compact icon buttons. Put disambiguation details in reason when needed.

            \(TranslationDirection.screenshotLanguageBehaviorInstructions)

            Format the answer field as clear Markdown.
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
        conversationContext: String?,
        forSelectionReplacement: Bool
    ) -> String {
        let direction = TranslationDirection.forUserInterface
        var instructions = [
            "- If the source text is primarily in \(direction.expectedSourceLanguage), translate it into natural \(direction.targetLanguage).",
            "- If the source text is primarily in \(direction.targetLanguage), translate it into natural \(direction.expectedSourceLanguage) instead.",
            "- For mixed English and Japanese text, translate into the language opposite the source text's primary language.",
            "- Do not return the source text unchanged unless it contains no translatable language.",
            "- Preserve the speaker's tone, intent, names, URLs, emoji, and formatting where helpful."
        ]

        if forSelectionReplacement {
            instructions.append("- Return only the translated text. Do not add labels, explanations, summaries, or Markdown headings.")
        } else {
            instructions.append("- If this appears to be a chat message, include a one-sentence summary only when it adds useful context.")
        }

        instructions.append("- Return clear Markdown only. Do not wrap the answer in JSON.")

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
                actionSuggestion: envelope.actionSuggestion
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
}

private struct ResponsesRequest: Encodable {
    let model: String
    let input: [ResponsesInput]
    let reasoning: ReasoningConfiguration?
    let serviceTier: String?

    private enum CodingKeys: String, CodingKey {
        case model
        case input
        case reasoning
        case serviceTier = "service_tier"
    }
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
            return "OpenAI returned an invalid response."
        case .httpStatus(let statusCode, let bodyPreview):
            if statusCode == 429 {
                return "OpenAI returned HTTP 429. This is usually a rate limit, quota issue, or unsupported priority processing. Set Speed to auto and try again.\(Self.formattedBodyPreview(bodyPreview))"
            }

            return "OpenAI request failed with HTTP status \(statusCode).\(Self.formattedBodyPreview(bodyPreview))"
        case .apiError(let statusCode, let message):
            if statusCode == 429 {
                return "OpenAI returned HTTP 429: \(message) Set Speed to auto if it is currently priority."
            }

            return "OpenAI request failed: \(message)"
        case .decodingFailed(let message, let bodyPreview):
            return "Sasu could not read OpenAI's response: \(message).\(Self.formattedBodyPreview(bodyPreview))"
        case .emptyOutput:
            return "OpenAI returned no answer."
        }
    }

    private static func formattedBodyPreview(_ bodyPreview: String?) -> String {
        guard let bodyPreview, !bodyPreview.isEmpty else {
            return ""
        }

        return "\n\nResponse body: \(bodyPreview.prefix(500))"
    }
}
