import Foundation

enum JapaneseReadingService {
    static func readings(for sourceText: String) -> [RubyTextSegment]? {
        let cfText = sourceText as CFString
        let fullRange = CFRange(location: 0, length: CFStringGetLength(cfText))
        guard fullRange.length > 0,
              let tokenizer = CFStringTokenizerCreate(
                nil,
                cfText,
                fullRange,
                kCFStringTokenizerUnitWord,
                Locale(identifier: "ja") as CFLocale
              ) else {
            return nil
        }

        var segments: [RubyTextSegment] = []
        var cursor = sourceText.startIndex
        var hasReading = false
        var tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)

        while tokenType.rawValue != 0 {
            let tokenCFRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let tokenNSRange = NSRange(location: tokenCFRange.location, length: tokenCFRange.length)
            guard let tokenRange = Range(tokenNSRange, in: sourceText),
                  tokenRange.lowerBound >= cursor,
                  tokenRange.upperBound > cursor else {
                tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
                continue
            }

            appendPlainText(String(sourceText[cursor..<tokenRange.lowerBound]), to: &segments)

            let tokenText = String(sourceText[tokenRange])
            let reading = readingForCurrentToken(tokenizer: tokenizer, tokenText: tokenText)
            if reading != nil {
                hasReading = true
            }
            segments.append(RubyTextSegment(text: tokenText, reading: reading))

            cursor = tokenRange.upperBound
            tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }

        appendPlainText(String(sourceText[cursor...]), to: &segments)
        return hasReading ? segments : nil
    }

    private static func readingForCurrentToken(
        tokenizer: CFStringTokenizer,
        tokenText: String
    ) -> String? {
        guard containsKanji(tokenText),
              let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer,
                kCFStringTokenizerAttributeLatinTranscription
              ) as? String else {
            return nil
        }

        let hiragana = latinToHiragana(latin)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hiragana.isEmpty, containsHiragana(hiragana) else {
            return nil
        }

        return hiragana
    }

    private static func latinToHiragana(_ latin: String) -> String {
        let mutable = NSMutableString(string: latin) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformLatinHiragana, false)
        return mutable as String
    }

    private static func appendPlainText(_ text: String, to segments: inout [RubyTextSegment]) {
        guard !text.isEmpty else { return }

        if let last = segments.last, last.reading == nil {
            segments[segments.count - 1] = RubyTextSegment(text: last.text + text, reading: nil)
        } else {
            segments.append(RubyTextSegment(text: text, reading: nil))
        }
    }

    private static func containsKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }

    private static func containsHiragana(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x309F).contains(scalar.value)
        }
    }
}
