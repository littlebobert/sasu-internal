import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class HighlightOverlayController {
    private var panel: NSPanel?

    func show(highlight: HighlightSuggestion, screenshot: ScreenshotPayload) {
        guard let screen = NSScreen.screen(displayID: screenshot.displayID) else {
            return
        }

        let mappedHighlight = MappedHighlight(
            suggestion: highlight,
            screenFrame: screen.frame,
            screenshotSize: (try? screenshot.uploadImage.pixelSize) ?? screenshot.pixelSize
        )

        if panel == nil {
            panel = makePanel(screen: screen)
        }

        panel?.animator().alphaValue = 1
        panel?.alphaValue = 1
        panel?.setFrame(screen.frame, display: true)
        panel?.contentView = NSHostingView(
            rootView: HighlightOverlayView(highlight: mappedHighlight)
        )
        panel?.orderFrontRegardless()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    private func makePanel(screen: NSScreen) -> NSPanel {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        return panel
    }
}

private struct MappedHighlight {
    let label: String
    let shape: HighlightShape
    let rect: CGRect
    let screenSize: CGSize
    let reason: String?

    init(suggestion: HighlightSuggestion, screenFrame: CGRect, screenshotSize: CGSize) {
        let scaleX = screenFrame.width / screenshotSize.width
        let scaleY = screenFrame.height / screenshotSize.height
        self.label = suggestion.label
        self.shape = suggestion.shape
        self.screenSize = screenFrame.size
        self.rect = CGRect(
            x: suggestion.x * scaleX,
            y: suggestion.y * scaleY,
            width: suggestion.width * scaleX,
            height: suggestion.height * scaleY
        )
        self.reason = suggestion.reason
    }
}

private struct HighlightOverlayView: View {
    let highlight: MappedHighlight

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            overlayShape
            label
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var overlayShape: some View {
        if highlight.shape == .circle {
            Ellipse()
                .stroke(Color.blue, lineWidth: 5)
                .background(Ellipse().fill(Color.blue.opacity(0.12)))
                .frame(width: highlight.rect.width, height: highlight.rect.height)
                .position(x: highlight.rect.midX, y: highlight.rect.midY)
        } else {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.blue, lineWidth: 5)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.12)))
                .frame(width: highlight.rect.width, height: highlight.rect.height)
                .position(x: highlight.rect.midX, y: highlight.rect.midY)
        }
    }

    private var label: some View {
        Text(highlight.label)
            .font(.headline)
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: max(120, highlight.screenSize.width - 32))
            .position(labelPosition)
    }

    private var labelPosition: CGPoint {
        let estimatedLabelWidth = min(max(CGFloat(highlight.label.count) * 10 + 20, 80), highlight.screenSize.width - 32)
        let halfLabelWidth = estimatedLabelWidth / 2
        let x = min(
            max(highlight.rect.midX, halfLabelWidth + 16),
            highlight.screenSize.width - halfLabelWidth - 16
        )
        let preferredY = highlight.rect.minY - 22
        let y = preferredY >= 24
            ? preferredY
            : min(highlight.rect.maxY + 22, highlight.screenSize.height - 24)

        return CGPoint(x: x, y: y)
    }
}

private extension NSScreen {
    static func screen(displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
    }
}
