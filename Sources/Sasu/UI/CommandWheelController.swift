import AppKit
import Carbon
import SwiftUI

enum SasuCommand: CaseIterable {
    case captureAndAsk
    case translateSelection
    case translateAndReplace

    var title: LocalizedStringResource {
        switch self {
        case .captureAndAsk:
            return "Capture & Ask"
        case .translateSelection:
            return "Translate Selection"
        case .translateAndReplace:
            return "Translate & Replace"
        }
    }

    var symbolName: String {
        switch self {
        case .captureAndAsk:
            return "camera.viewfinder"
        case .translateSelection:
            return "translate"
        case .translateAndReplace:
            return "character.cursor.ibeam"
        }
    }
}

@MainActor
private final class CommandWheelState: ObservableObject {
    @Published var highlightedCommand: SasuCommand = .captureAndAsk
}

@MainActor
final class CommandWheelController {
    private static let clockwiseCommands: [SasuCommand] = [
        .captureAndAsk,
        .translateAndReplace,
        .translateSelection
    ]

    private var panel: CommandWheelPanel?
    private var outsideClickMonitor: Any?
    private var mouseMoveMonitor: Any?
    private var localEventMonitor: Any?
    private var appActivationObserver: NSObjectProtocol?
    private var modifierPollingTimer: Timer?
    private var selectionHandler: ((SasuCommand) -> Void)?
    private let wheelState = CommandWheelState()
    private var selectionOrigin = NSPoint.zero
    private var requiredModifierFlags: NSEvent.ModifierFlags = []
    private var shouldInvokeOnModifierRelease = false
    private var isInvokingSelection = false

    func presentOrAdvance(
        hotkeyModifiers: UInt32,
        onSelect: @escaping (SasuCommand) -> Void
    ) {
        if panel?.isVisible == true {
            requiredModifierFlags = Self.eventModifierFlags(from: hotkeyModifiers)
            shouldInvokeOnModifierRelease = true
            advanceSelectionClockwise()
            startModifierPolling()
            return
        }

        selectionHandler = onSelect
        selectionOrigin = NSEvent.mouseLocation
        requiredModifierFlags = Self.eventModifierFlags(from: hotkeyModifiers)
        shouldInvokeOnModifierRelease = false
        wheelState.highlightedCommand = .captureAndAsk
        isInvokingSelection = false

        if panel == nil {
            panel = makePanel()
        }

        guard let panel else { return }
        panel.contentView = NSHostingView(
            rootView: CommandWheelView(
                state: wheelState,
                onSelect: { [weak self] command in
                    self?.invoke(command)
                }
            )
        )
        positionPanel(panel)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().alphaValue = 1
        }

        startEventMonitoring()
        startModifierPolling()
    }

    func hide() {
        stopEventMonitoring()
        stopModifierPolling()
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    private func advanceSelectionClockwise() {
        guard let index = Self.clockwiseCommands.firstIndex(of: wheelState.highlightedCommand) else {
            wheelState.highlightedCommand = .captureAndAsk
            return
        }
        let nextIndex = Self.clockwiseCommands.index(after: index)
        wheelState.highlightedCommand = nextIndex == Self.clockwiseCommands.endIndex
            ? Self.clockwiseCommands[0]
            : Self.clockwiseCommands[nextIndex]
    }

    private func makePanel() -> CommandWheelPanel {
        let panel = CommandWheelPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 262, height: 262)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        var frame = panel.frame
        frame.origin = NSPoint(
            x: selectionOrigin.x - frame.width / 2,
            y: selectionOrigin.y - frame.height / 2
        )

        if let screen = NSScreen.screens.first(where: { NSMouseInRect(selectionOrigin, $0.frame, false) }) ?? NSScreen.main {
            frame.origin.x = min(max(frame.origin.x, screen.visibleFrame.minX + 6), screen.visibleFrame.maxX - frame.width - 6)
            frame.origin.y = min(max(frame.origin.y, screen.visibleFrame.minY + 6), screen.visibleFrame.maxY - frame.height - 6)
        }

        panel.setFrame(frame, display: true)
    }

    private func startEventMonitoring() {
        stopEventMonitoring()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
        mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseMovement()
            }
        }
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .mouseMoved]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .mouseMoved {
                handleMouseMovement()
                return event
            }
            if event.type == .keyDown {
                return handleKeyDown(event)
            }
            if event.window !== panel {
                hide()
            }
            return event
        }
    }

    private func stopEventMonitoring() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let mouseMoveMonitor {
            NSEvent.removeMonitor(mouseMoveMonitor)
            self.mouseMoveMonitor = nil
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case UInt16(kVK_UpArrow):
            wheelState.highlightedCommand = .captureAndAsk
            shouldInvokeOnModifierRelease = true
            return nil
        case UInt16(kVK_LeftArrow):
            wheelState.highlightedCommand = .translateSelection
            shouldInvokeOnModifierRelease = true
            return nil
        case UInt16(kVK_DownArrow), UInt16(kVK_RightArrow):
            wheelState.highlightedCommand = .translateAndReplace
            shouldInvokeOnModifierRelease = true
            return nil
        case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
            invoke(wheelState.highlightedCommand)
            return nil
        case UInt16(kVK_Escape):
            hide()
            return nil
        default:
            return event
        }
    }

    private func handleMouseMovement() {
        guard panel?.isVisible == true, !isInvokingSelection else { return }

        let location = NSEvent.mouseLocation
        let deltaX = location.x - selectionOrigin.x
        let deltaY = location.y - selectionOrigin.y
        let distance = hypot(deltaX, deltaY)
        guard distance > 24 else { return }

        if deltaY > abs(deltaX) * 0.35 {
            wheelState.highlightedCommand = .captureAndAsk
        } else if deltaX < 0 {
            wheelState.highlightedCommand = .translateSelection
        } else {
            wheelState.highlightedCommand = .translateAndReplace
        }

        if distance >= 150 {
            invoke(wheelState.highlightedCommand)
        }
    }

    private func startModifierPolling() {
        stopModifierPolling()
        guard !requiredModifierFlags.isEmpty else { return }

        modifierPollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollModifierState()
            }
        }
        if let modifierPollingTimer {
            RunLoop.main.add(modifierPollingTimer, forMode: .common)
        }
    }

    private func stopModifierPolling() {
        modifierPollingTimer?.invalidate()
        modifierPollingTimer = nil
    }

    private func pollModifierState() {
        guard panel?.isVisible == true, !isInvokingSelection else { return }

        let currentFlags = NSEvent.ModifierFlags(
            rawValue: UInt(CGEventSource.flagsState(.combinedSessionState).rawValue)
        )
        if currentFlags.intersection(requiredModifierFlags) != requiredModifierFlags {
            if shouldInvokeOnModifierRelease {
                invoke(wheelState.highlightedCommand)
            } else {
                stopModifierPolling()
            }
        }
    }

    private func invoke(_ command: SasuCommand) {
        guard !isInvokingSelection else { return }
        isInvokingSelection = true
        let handler = selectionHandler
        hide()
        handler?(command)
    }

    private static func eventModifierFlags(from carbonModifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 {
            flags.insert(.control)
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            flags.insert(.option)
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            flags.insert(.shift)
        }
        if carbonModifiers & UInt32(cmdKey) != 0 {
            flags.insert(.command)
        }
        return flags
    }
}

private final class CommandWheelPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct CommandWheelView: View {
    @ObservedObject var state: CommandWheelState
    let onSelect: (SasuCommand) -> Void

    var body: some View {
        ZStack {
            wheelSegment(
                command: .captureAndAsk,
                startAngle: .degrees(210),
                endAngle: .degrees(330)
            )
            wheelSegment(
                command: .translateSelection,
                startAngle: .degrees(90),
                endAngle: .degrees(210)
            )
            wheelSegment(
                command: .translateAndReplace,
                startAngle: .degrees(330),
                endAngle: .degrees(450)
            )

            commandLabel(.captureAndAsk, width: 120)
                .offset(y: -62)
            commandLabel(.translateSelection, width: 105)
                .offset(x: -57, y: 43)
            commandLabel(.translateAndReplace, width: 105)
                .offset(x: 57, y: 43)
        }
        .frame(width: 262, height: 262)
    }

    private func wheelSegment(
        command: SasuCommand,
        startAngle: Angle,
        endAngle: Angle
    ) -> some View {
        let isHighlighted = state.highlightedCommand == command

        let segment = WheelSegment(startAngle: startAngle, endAngle: endAngle)

        return VisualEffectBlur()
            .opacity(0.74)
            .clipShape(segment)
            .overlay {
                segment
                    .fill(Color.accentColor.opacity(isHighlighted ? 0.52 : 0.04))
            }
            .contentShape(segment)
            .onTapGesture {
                onSelect(command)
            }
    }

    private func commandLabel(_ command: SasuCommand, width: CGFloat) -> some View {
        let isHighlighted = state.highlightedCommand == command

        return VStack(spacing: 5) {
            Image(systemName: command.symbolName)
                .font(.body.bold())
            Text(command.title)
                .font(.caption.bold())
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(isHighlighted ? Color.white : Color.primary)
        .frame(width: width)
        .allowsHitTesting(false)
    }
}

private struct WheelSegment: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 5
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
