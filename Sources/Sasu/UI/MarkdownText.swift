import AppKit
import SwiftUI

struct MarkdownText: View {
    let markdown: String
    var fontSize: CGFloat = NSFont.systemFontSize
    var onUserScroll: (() -> Void)?

    var body: some View {
        MarkdownTextView(
            markdown: markdown,
            fontSize: fontSize,
            onUserScroll: onUserScroll
        )
    }
}

private struct MarkdownTextView: NSViewRepresentable {
    let markdown: String
    let fontSize: CGFloat
    let onUserScroll: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LinkTextView {
        let textView = LinkTextView()
        textView.delegate = context.coordinator
        textView.onUserScroll = onUserScroll
        return textView
    }

    func updateNSView(_ textView: LinkTextView, context: Context) {
        textView.onUserScroll = onUserScroll
        textView.textStorage?.setAttributedString(Self.attributedMarkdown(for: markdown, fontSize: fontSize))
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

    private static func attributedMarkdown(for markdown: String, fontSize: CGFloat) -> NSAttributedString {
        let normalizedMarkdown = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let attributedString: AttributedString
        do {
            attributedString = try AttributedString(
                markdown: normalizedMarkdown,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        } catch {
            attributedString = AttributedString(normalizedMarkdown)
        }

        let result = NSMutableAttributedString(attributedString: NSAttributedString(attributedString))
        let fullRange = NSRange(location: 0, length: result.length)
        guard fullRange.length > 0 else { return result }

        result.addAttributes(
            [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ],
            range: fullRange
        )
        addDetectedLinks(to: result)

        return result
    }

    private static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 4
        style.lineSpacing = 0
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
    var onUserScroll: (() -> Void)?
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
            title: String(localized: "Copy Link"),
            action: #selector(copyLink(_:)),
            keyEquivalent: ""
        )
        copyLinkItem.target = self
        copyLinkItem.representedObject = url
        menu.insertItem(copyLinkItem, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isPointInsideRenderedText(point) else {
            return nil
        }

        return super.hitTest(point)
    }

    override func scrollWheel(with event: NSEvent) {
        onUserScroll?()
        nextResponder?.scrollWheel(with: event)
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

    private func isPointInsideRenderedText(_ point: NSPoint) -> Bool {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else {
            return false
        }

        textContainer.containerSize = NSSize(
            width: bounds.width,
            height: .greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: textContainer)

        let usedRect = layoutManager.usedRect(for: textContainer)
        let hitRect = usedRect
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            .insetBy(dx: -4, dy: -4)
        return hitRect.contains(point)
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
