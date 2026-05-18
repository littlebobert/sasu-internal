import AppKit
import SwiftUI

struct MarkdownText: View {
    let markdown: String

    var body: some View {
        MarkdownTextView(markdown: markdown)
    }
}

private struct MarkdownTextView: NSViewRepresentable {
    let markdown: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LinkTextView {
        let textView = LinkTextView()
        textView.delegate = context.coordinator
        return textView
    }

    func updateNSView(_ textView: LinkTextView, context: Context) {
        textView.textStorage?.setAttributedString(Self.attributedMarkdown(for: markdown))
        textView.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView textView: LinkTextView,
        context: Context
    ) -> CGSize? {
        let width = max(proposal.width ?? textView.bounds.width, 300)
        return CGSize(
            width: width,
            height: textView.heightThatFits(width: width)
        )
    }

    private static func attributedMarkdown(for markdown: String) -> NSAttributedString {
        let normalizedMarkdown = repairMissingSpaces(in: markdownWithSafeSoftBreaks(markdown))
        let attributedString: AttributedString
        do {
            attributedString = try AttributedString(
                markdown: normalizedMarkdown,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
            )
        } catch {
            attributedString = AttributedString(normalizedMarkdown)
        }

        let result = NSMutableAttributedString(attributedString: NSAttributedString(attributedString))
        let fullRange = NSRange(location: 0, length: result.length)
        guard fullRange.length > 0 else { return result }

        result.addAttributes(
            [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ],
            range: fullRange
        )
        addDetectedLinks(to: result)

        return result
    }

    private static func repairMissingSpaces(in text: String) -> String {
        var repairedText = text

        [
            (#"([.!?])(?=(?:[*_~`]+)?[A-Z])"#, "$1 "),
            (#"(:)(?=(?:[*_~`]+)?(?:https?://|[A-Z]))"#, "$1 "),
            (#"(\.(?:jp|com|org|net|io|dev|app|ai))(?=(?:[*_~`]+)?[A-Z])"#, "$1 "),
            (#"(\.(?:html?|php|aspx))(?=(?:[*_~`]+)?[A-Z])"#, "$1 "),
            (#"(\.(?:jp|com|org|net|io|dev|app|ai|html?|php|aspx))(?=(?:[Ii]nto|[Tt]o|[Ii]f|[Dd]o|[Kk]eep|[Aa]lso|[Tt]hey|[Nn]ow))"#, "$1 "),
            (#"\b([Ii]nto|[Tt]o)(?=https?://)"#, "$1 ")
        ].forEach { pattern, replacement in
            repairedText = repairedText.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }

        return repairedText
    }

    private static func markdownWithSafeSoftBreaks(_ markdown: String) -> String {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        guard lines.count > 1 else {
            return markdown
        }

        var result = ""
        var isInsideFence = false

        for index in lines.indices {
            let line = lines[index]
            result += line

            guard index < lines.index(before: lines.endIndex) else {
                break
            }

            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            let nextLine = lines[lines.index(after: index)]
            let trimmedNextLine = nextLine.trimmingCharacters(in: .whitespaces)

            if isFenceDelimiter(trimmedLine) {
                isInsideFence.toggle()
                result += "\n"
            } else if shouldPreserveLineBreak(
                currentLine: trimmedLine,
                nextLine: trimmedNextLine,
                isInsideFence: isInsideFence
            ) {
                result += "\n"
            } else {
                result += " "
            }
        }

        return result
    }

    private static func shouldPreserveLineBreak(
        currentLine: String,
        nextLine: String,
        isInsideFence: Bool
    ) -> Bool {
        isInsideFence
            || currentLine.isEmpty
            || nextLine.isEmpty
            || currentLine.hasSuffix("\\")
            || currentLine.hasSuffix("  ")
            || isMarkdownBlockBoundary(currentLine)
            || isMarkdownBlockBoundary(nextLine)
    }

    private static func isFenceDelimiter(_ line: String) -> Bool {
        line.hasPrefix("```") || line.hasPrefix("~~~")
    }

    private static func isMarkdownBlockBoundary(_ line: String) -> Bool {
        line.hasPrefix("#")
            || line.hasPrefix(">")
            || line.hasPrefix("- ")
            || line.hasPrefix("* ")
            || line.hasPrefix("+ ")
            || line.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil
    }

    private static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 8
        style.lineBreakMode = .byWordWrapping
        return style
    }

    private static func addDetectedLinks(to attributedString: NSMutableAttributedString) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return
        }

        let string = attributedString.string
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        detector.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let match, let url = match.url else { return }
            attributedString.addAttribute(.link, value: url, range: match.range)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        func textView(
            _ textView: NSTextView,
            clickedOnLink link: Any,
            at charIndex: Int
        ) -> Bool {
            guard let url = Self.url(from: link) else {
                return false
            }

            NSWorkspace.shared.open(url)
            return true
        }

        private static func url(from link: Any) -> URL? {
            if let url = link as? URL {
                return url
            }

            if let string = link as? String {
                return URL(string: string)
            }

            return nil
        }
    }
}

private final class LinkTextView: NSTextView {
    private var hoverTrackingArea: NSTrackingArea?

    convenience init() {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: .zero)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        self.init(frame: .zero, textContainer: textContainer)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func heightThatFits(width: CGFloat) -> CGFloat {
        guard let layoutManager, let textContainer else {
            return textStorage?.length == 0 ? 0 : 18
        }

        textContainer.containerSize = NSSize(
            width: width,
            height: .greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: textContainer)

        let measuredHeight = ceil(layoutManager.usedRect(for: textContainer).height)
        return max(measuredHeight, textStorage?.length == 0 ? 0 : 18)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateCursor(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSCursor.arrow.set()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard let url = linkURL(at: event) else {
            return menu
        }

        let copyLinkItem = NSMenuItem(
            title: "Copy Link",
            action: #selector(copyLink(_:)),
            keyEquivalent: ""
        )
        copyLinkItem.target = self
        copyLinkItem.representedObject = url
        menu.insertItem(copyLinkItem, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    @objc private func copyLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    private func configure() {
        isEditable = false
        isSelectable = true
        drawsBackground = false
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = false
        isHorizontallyResizable = false
        isVerticallyResizable = true
        linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    }

    private func updateCursor(for event: NSEvent) {
        if linkURL(at: event) != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
    }

    private func linkURL(at event: NSEvent) -> URL? {
        guard let layoutManager, let textContainer, let textStorage else {
            return nil
        }

        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer
        )
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else {
            return nil
        }

        let link = textStorage.attribute(.link, at: characterIndex, effectiveRange: nil)
        if let url = link as? URL {
            return url
        }

        if let string = link as? String {
            return URL(string: string)
        }

        return nil
    }
}
