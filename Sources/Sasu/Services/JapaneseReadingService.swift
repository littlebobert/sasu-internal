import Foundation

/// Furigana come from the model; this checks what it returned before the
/// transcript shows it.
enum JapaneseReadingService {
    /// Validates readings a model returned for `sourceText`. Returns nil
    /// unless the segments rebuild the source exactly and every reading is
    /// hiragana on a segment that contains kanji.
    static func validatedModelReadings(
        _ modelSegments: [RubyTextSegment],
        for sourceText: String
    ) -> [RubyTextSegment]? {
        guard modelSegments.map(\.text).joined() == sourceText else { return nil }

        var segments: [RubyTextSegment] = []
        var hasReading = false
        for segment in modelSegments where !segment.text.isEmpty {
            let reading = segment.reading?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let reading, !reading.isEmpty, containsKanji(segment.text) else {
                appendPlainText(segment.text, to: &segments)
                continue
            }
            guard isHiraganaReading(reading) else { return nil }
            hasReading = true
            segments.append(RubyTextSegment(text: segment.text, reading: reading))
        }

        return hasReading ? segments : nil
    }

    static func containsKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }

    private static func isHiraganaReading(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            (0x3041...0x309F).contains(scalar.value) || scalar.value == 0x30FC
        }
    }

    private static func appendPlainText(_ text: String, to segments: inout [RubyTextSegment]) {
        guard !text.isEmpty else { return }

        if let last = segments.last, last.reading == nil {
            segments[segments.count - 1] = RubyTextSegment(text: last.text + text, reading: nil)
        } else {
            segments.append(RubyTextSegment(text: text, reading: nil))
        }
    }
}
