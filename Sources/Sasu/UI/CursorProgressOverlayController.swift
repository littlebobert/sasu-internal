import AppKit

@MainActor
final class CursorProgressOverlayController {
    private var panel: NSPanel?
    private var trackingTimer: Timer?

    private let panelSize = NSSize(width: 22, height: 22)
    private let cursorOffset = NSPoint(x: 16, y: -18)

    func show() {
        if panel == nil {
            panel = makePanel()
        }

        updatePosition()
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel?.animator().alphaValue = 1
        }

        startTracking()
    }

    func hide() {
        stopTracking()

        guard let panel, panel.isVisible else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.contentView = CursorProgressContentView(frame: NSRect(origin: .zero, size: panelSize))
        return panel
    }

    private func startTracking() {
        stopTracking()

        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePosition()
            }
        }

        if let trackingTimer {
            RunLoop.main.add(trackingTimer, forMode: .common)
        }
    }

    private func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    private func updatePosition() {
        let mouseLocation = NSEvent.mouseLocation
        var frame = NSRect(origin: .zero, size: panelSize)
        frame.origin.x = mouseLocation.x + cursorOffset.x
        frame.origin.y = mouseLocation.y + cursorOffset.y

        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            frame.origin.x = min(max(frame.origin.x, screen.frame.minX + 4), screen.frame.maxX - frame.width - 4)
            frame.origin.y = min(max(frame.origin.y, screen.frame.minY + 4), screen.frame.maxY - frame.height - 4)
        }

        panel?.setFrame(frame, display: true)
    }
}

private final class CursorProgressContentView: NSView {
    private let spinner = NSProgressIndicator()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        spinner.startAnimation(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { false }
}
