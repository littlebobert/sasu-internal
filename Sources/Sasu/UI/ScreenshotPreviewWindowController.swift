import AppKit
import SwiftUI

@MainActor
final class ScreenshotPreviewWindowController {
    private var window: NSWindow?

    func show(image: NSImage) {
        if window == nil {
            window = makeWindow(for: image)
        }

        window?.contentView = NSHostingView(
            rootView: ScreenshotPreviewView(image: image)
        )
        window?.setFrame(initialFrame(for: image), display: true)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow(for image: NSImage) -> NSWindow {
        let window = NSWindow(
            contentRect: initialFrame(for: image),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Screenshot Preview"
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.isReleasedWhenClosed = false
        return window
    }

    private func initialFrame(for image: NSImage) -> NSRect {
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let imageSize = image.size
        let aspectRatio = max(imageSize.width, 1) / max(imageSize.height, 1)
        let maxWidth = min(screenFrame.width * 0.72, 1100)
        let maxHeight = min(screenFrame.height * 0.72, 760)

        var width = maxWidth
        var height = width / aspectRatio
        if height > maxHeight {
            height = maxHeight
            width = height * aspectRatio
        }

        width = max(width, 520)
        height = max(height, 360)

        return NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2,
            width: width,
            height: height
        )
    }
}

private struct ScreenshotPreviewView: View {
    let image: NSImage

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(14)
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}
