import CoreText
import SwiftUI

struct RubyTextView: View {
    let segments: [RubyTextSegment]
    var fontSize: CGFloat = 13
    var findQuery = ""
    var selectedFindOccurrence: Int?
    /// Lays the readings out without drawing them, to hold their space
    /// while the real ones are on their way.
    var hidesReadings = false
    @State private var height: CGFloat = 44

    var body: some View {
        RubyCoreTextView(
            segments: segments,
            fontSize: fontSize,
            findQuery: findQuery,
            selectedFindOccurrence: selectedFindOccurrence,
            hidesReadings: hidesReadings,
            height: $height
        )
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RubyCoreTextView: NSViewRepresentable {
    let segments: [RubyTextSegment]
    let fontSize: CGFloat
    let findQuery: String
    let selectedFindOccurrence: Int?
    let hidesReadings: Bool
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeNSView(context: Context) -> CoreTextRubyDrawingView {
        let view = CoreTextRubyDrawingView()
        view.heightDidChange = { [weak coordinator = context.coordinator] height in
            coordinator?.setHeight(height)
        }
        return view
    }

    func updateNSView(_ view: CoreTextRubyDrawingView, context: Context) {
        let attributedString = Self.attributedString(
            for: segments,
            fontSize: fontSize,
            hidesReadings: hidesReadings
        )
        applyTranscriptFindHighlight(
            to: attributedString,
            query: findQuery,
            selectedOccurrence: selectedFindOccurrence
        )
        guard context.coordinator.currentAttributedString != attributedString else {
            view.updateMeasuredHeight()
            return
        }

        context.coordinator.currentAttributedString = attributedString
        view.attributedString = attributedString
    }

    private static func attributedString(
        for segments: [RubyTextSegment],
        fontSize: CGFloat,
        hidesReadings: Bool
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = fontSize * (12.0 / 13.0)

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]

        for segment in segments {
            var attributes = baseAttributes
            if let annotation = rubyAnnotation(for: segment.reading, hidden: hidesReadings) {
                attributes[NSAttributedString.Key(rawValue: kCTRubyAnnotationAttributeName as String)] = annotation
            }

            result.append(NSAttributedString(string: segment.text, attributes: attributes))
        }

        return result
    }

    private static let rubySizeFactor: CGFloat = 0.55

    private static func rubyAnnotation(for reading: String?, hidden: Bool) -> CTRubyAnnotation? {
        guard let reading = reading?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reading.isEmpty else { return nil }

        if hidden {
            let attributes: [CFString: Any] = [
                kCTRubyAnnotationSizeFactorAttributeName: rubySizeFactor,
                kCTForegroundColorAttributeName: NSColor.clear.cgColor
            ]
            return CTRubyAnnotationCreateWithAttributes(
                .auto,
                .auto,
                .before,
                reading as CFString,
                attributes as CFDictionary
            )
        }

        let topText = reading as CFString
        var values: [Unmanaged<CFString>?] = [
            Unmanaged.passUnretained(topText),
            nil,
            nil,
            nil
        ]

        return values.withUnsafeMutableBufferPointer { buffer in
            CTRubyAnnotationCreate(.auto, .auto, rubySizeFactor, buffer.baseAddress!)
        }
    }

    final class Coordinator {
        var currentAttributedString = NSAttributedString()
        private var height: Binding<CGFloat>

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        func setHeight(_ newHeight: CGFloat) {
            DispatchQueue.main.async {
                self.height.wrappedValue = max(44, newHeight)
            }
        }
    }
}

private final class CoreTextRubyDrawingView: NSView {
    var heightDidChange: ((CGFloat) -> Void)?
    var attributedString = NSAttributedString() {
        didSet {
            framesetter = CTFramesetterCreateWithAttributedString(attributedString)
            updateMeasuredHeight()
            needsDisplay = true
        }
    }
    private var framesetter = CTFramesetterCreateWithAttributedString(NSAttributedString())

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateMeasuredHeight()
    }

    func updateMeasuredHeight() {
        guard bounds.width > 0 else {
            heightDidChange?(44)
            return
        }

        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedString.length),
            nil,
            CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude),
            nil
        )
        heightDidChange?(ceil(suggestedSize.height) + 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              attributedString.length > 0 else {
            return
        }

        context.saveGState()
        context.textMatrix = .identity

        let drawingBounds = bounds.insetBy(dx: 0, dy: 1)
        let path = CGPath(rect: drawingBounds, transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributedString.length),
            path,
            nil
        )
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}
