import AppKit

@MainActor
final class CursorProgressOverlayController {
    private var panel: NSPanel?
    private var trackingTimer: Timer?

    private var panelSize = NSSize(width: 110, height: 32)
    private let cursorOffset = NSPoint(x: 16, y: -18)
    private let statusFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    func show(status: String = String(localized: "Working…")) {
        if panel == nil {
            panel = makePanel()
        }

        resizePanel(toFit: status)
        (panel?.contentView as? CursorProgressContentView)?.update(status: status)
        updatePosition()
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel?.animator().alphaValue = 1
        }

        startTracking()
    }

    func update(status: String) {
        resizePanel(toFit: status)
        (panel?.contentView as? CursorProgressContentView)?.update(status: status)
        updatePosition()
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

    private func resizePanel(toFit status: String) {
        let textWidth = ceil(
            (status as NSString).size(withAttributes: [.font: statusFont]).width
        )
        panelSize.width = min(max(textWidth + 42, 88), 260)

        guard let panel else { return }
        var frame = panel.frame
        frame.size = panelSize
        panel.setFrame(frame, display: true)
    }
}

private final class CursorProgressContentView: NSView {
    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)

        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .labelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            spinner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 6),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        spinner.startAnimation(nil)
    }

    func update(status: String) {
        statusLabel.stringValue = status
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { false }
}
