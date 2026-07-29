import Foundation

enum AIRequestCredential {
    case openAIAPIKey(String)
    case anthropicAPIKey(String)
    case backendAccessToken(String, baseURL: URL)
}

enum AIRequestSupport {
    static func buildScreenshotPrompt(
        prompt: String,
        screenshot: ScreenshotPayload,
        translationSourceLanguage: TranslationSourceLanguage,
        conversationContext: String?
    ) throws -> String {
        let uploadImage = try screenshot.uploadImage
        var parts: [String]

        if screenshot.isImportedImage {
            parts = [
                "User request:",
                prompt,
                "",
                "Image context:",
                "- This is an image the user dropped or imported into Sasu, not a live screen capture.",
                "- There is no cursor marker and no frontmost-app metadata.",
                "- Original image size: \(Int(screenshot.pixelSize.width)) x \(Int(screenshot.pixelSize.height)) pixels",
                "- Uploaded image size: \(Int(uploadImage.pixelSize.width)) x \(Int(uploadImage.pixelSize.height)) pixels",
                "- Uploaded image format: JPEG, resized for faster requests",
                "",
                """
                Return a JSON object only, with this shape:
                {
                  "answer": "Markdown answer for the user",
                  "sourceText": "exact visible source text when translating text from the image, otherwise null",
                  "actionSuggestion": null
                }

                Prefer translating readable text and explaining what the image shows. Set actionSuggestion to null unless the image is clearly a UI screenshot and the user asks where to click or what to do next.

                For sourceText, when translating text from the image, copy the exact visible source text being translated. Preserve its original characters and line breaks. For other requests, set sourceText to null.

                \(TranslationDirection.screenshotLanguageBehaviorInstructions(
                    for: TranslationDirection.preferredUserInterfaceLanguages,
                    sourceLanguage: translationSourceLanguage
                ))

                Format the answer field using inline Markdown compatible with the transcript: paragraphs separated by blank lines, emphasis, bold, inline code, and links. Do not use Markdown headings, lists, block quotes, tables, fenced code blocks, thematic rules, or HTML.
                """
            ]
        } else {
            parts = [
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
            let attachedImageGuidance = screenshot.isImportedImage
                ? "Use this context to understand the user's overall goal and prior steps. The attached image is what the user just provided and should be treated as the source of truth for this request."
                : "Use this context to understand the user's overall goal and prior steps. The attached screenshot is the current screen and should be treated as the source of truth for what is visible now."
            parts.insert(
                contentsOf: [
                    "",
                    "Conversation context so far:",
                    conversationContext,
                    "",
                    attachedImageGuidance
                ],
                at: 0
            )
        }

        return parts.joined(separator: "\n")
    }

    static func buildClipboardTranslationPrompt(
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

    static func parseAssistantResult(from text: String) -> AssistantResult {
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

    static func partialAnswer(from streamedJSON: String) -> String? {
        partialStringValue(forKey: "answer", from: streamedJSON)
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
                guard let (scalar, nextIndex) = unicodeScalar(
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
