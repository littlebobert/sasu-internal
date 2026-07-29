import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SelectAllTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let selectAllTrigger: Int
    let isEnabled: Bool
    let onSubmit: () -> Void
    var onImageDrop: ((Data) -> Void)?
    var onImageDropTargeted: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onSubmit: onSubmit,
            onImageDrop: onImageDrop,
            onImageDropTargeted: onImageDropTargeted
        )
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
        textView.onImageDrop = { data in
            context.coordinator.onImageDrop?(data)
        }
        textView.onImageDropTargeted = { isTargeted in
            context.coordinator.onImageDropTargeted?(isTargeted)
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
        textView.registerForDraggedTypes([
            .fileURL,
            .png,
            .tiff,
            NSPasteboard.PasteboardType(UTType.image.identifier),
            NSPasteboard.PasteboardType(UTType.jpeg.identifier),
            NSPasteboard.PasteboardType(UTType.webP.identifier),
            NSPasteboard.PasteboardType(UTType.heic.identifier)
        ])

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onImageDrop = onImageDrop
        context.coordinator.onImageDropTargeted = onImageDropTargeted
        guard let textView = scrollView.documentView as? SubmitTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        textView.placeholderString = placeholder
        textView.isEditable = isEnabled
        textView.onSubmit = onSubmit
        textView.onImageDrop = { data in
            context.coordinator.onImageDrop?(data)
        }
        textView.onImageDropTargeted = { isTargeted in
            context.coordinator.onImageDropTargeted?(isTargeted)
        }
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
        var onImageDrop: ((Data) -> Void)?
        var onImageDropTargeted: ((Bool) -> Void)?
        var lastSelectAllTrigger = 0

        init(
            text: Binding<String>,
            onSubmit: @escaping () -> Void,
            onImageDrop: ((Data) -> Void)?,
            onImageDropTargeted: ((Bool) -> Void)?
        ) {
            self.text = text
            self.onSubmit = onSubmit
            self.onImageDrop = onImageDrop
            self.onImageDropTargeted = onImageDropTargeted
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
    var onImageDrop: ((Data) -> Void)?
    var onImageDropTargeted: ((Bool) -> Void)?

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

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard imageData(from: sender.draggingPasteboard) != nil else {
            onImageDropTargeted?(false)
            return []
        }
        onImageDropTargeted?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard imageData(from: sender.draggingPasteboard) != nil else {
            onImageDropTargeted?(false)
            return []
        }
        onImageDropTargeted?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onImageDropTargeted?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onImageDropTargeted?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        imageData(from: sender.draggingPasteboard) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onImageDropTargeted?(false)
        guard let data = imageData(from: sender.draggingPasteboard) else {
            return false
        }
        onImageDrop?(data)
        return true
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let data = imageData(from: pasteboard) {
            onImageDrop?(data)
            return
        }
        super.paste(sender)
    }

    private func imageData(from pasteboard: NSPasteboard) -> Data? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] {
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                if let data = try? Data(contentsOf: url), NSImage(data: data) != nil {
                    return data
                }
            }
        }

        let typeCandidates: [NSPasteboard.PasteboardType] = [
            .png,
            .tiff,
            NSPasteboard.PasteboardType(UTType.jpeg.identifier),
            NSPasteboard.PasteboardType(UTType.webP.identifier),
            NSPasteboard.PasteboardType(UTType.heic.identifier),
            NSPasteboard.PasteboardType(UTType.image.identifier)
        ]
        for type in typeCandidates {
            if let data = pasteboard.data(forType: type), NSImage(data: data) != nil {
                return data
            }
        }

        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            return pngData
        }

        return nil
    }
}
