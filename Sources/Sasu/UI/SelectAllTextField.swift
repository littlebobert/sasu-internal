import AppKit
import SwiftUI

struct SelectAllTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let selectAllTrigger: Int
    let isEnabled: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true

        let textView = SubmitTextView()
        textView.placeholderString = placeholder
        textView.delegate = context.coordinator
        textView.onSubmit = {
            context.coordinator.onSubmit()
        }
        textView.isEditable = isEnabled
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        guard let textView = scrollView.documentView as? SubmitTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        textView.placeholderString = placeholder
        textView.isEditable = isEnabled
        textView.onSubmit = onSubmit
        textView.needsDisplay = true

        guard context.coordinator.lastSelectAllTrigger != selectAllTrigger else {
            return
        }

        context.coordinator.lastSelectAllTrigger = selectAllTrigger
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            textView.selectAll(nil)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        var lastSelectAllTrigger = 0

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            textView.needsDisplay = true
        }
    }
}

private final class SubmitTextView: NSTextView {
    var placeholderString = ""
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let isShiftReturn = event.modifierFlags.contains(.shift)

        if isReturn, !isShiftReturn {
            onSubmit?()
            return
        }

        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty, !placeholderString.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        let origin = CGPoint(
            x: textContainerInset.width + 4,
            y: textContainerInset.height
        )
        placeholderString.draw(at: origin, withAttributes: attributes)
    }
}
