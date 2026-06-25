import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

struct ScreenshotService {
    func captureMainDisplay() async throws -> ScreenshotPayload {
        let hadPermissionBeforeRequest = CGPreflightScreenCaptureAccess()
        if !hadPermissionBeforeRequest, !ScreenRecordingPermissionStore.hasRequestedAccess {
            ScreenRecordingPermissionStore.markAccessRequested()
            _ = CGRequestScreenCaptureAccess()
        }

        let displayID = CGMainDisplayID()
        let mouseLocation = NSEvent.mouseLocation
        let image = try await Self.captureImage(
            displayID: displayID,
            hadPermissionBeforeRequest: hadPermissionBeforeRequest
        )

        let cursorImageLocation = Self.cursorImageLocation(
            mouseLocation: mouseLocation,
            displayID: displayID,
            image: image
        )
        let annotatedImage = Self.drawCursorMarker(
            on: image,
            cursorImageLocation: cursorImageLocation
        ) ?? image
        let bitmap = NSBitmapImageRep(cgImage: annotatedImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ScreenshotError.encodingFailed
        }

        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let frontmostApplicationName = frontmostApplication?.localizedName
        let frontmostWindowTitle = Self.frontmostWindowTitle(processIdentifier: frontmostApplication?.processIdentifier)

        return ScreenshotPayload(
            pngData: pngData,
            displayID: displayID,
            pixelSize: CGSize(width: image.width, height: image.height),
            frontmostApplicationName: frontmostApplicationName,
            frontmostWindowTitle: frontmostWindowTitle,
            mouseLocation: mouseLocation,
            cursorImageLocation: cursorImageLocation
        )
    }

    private static func captureImage(
        displayID: CGDirectDisplayID,
        hadPermissionBeforeRequest: Bool
    ) async throws -> CGImage {
        if #available(macOS 14.0, *) {
            do {
                return try await captureImageWithScreenCaptureKit(displayID: displayID)
            } catch {
                if !hadPermissionBeforeRequest || !CGPreflightScreenCaptureAccess() {
                    throw ScreenshotError.permissionDenied
                }

                throw ScreenshotError.captureFailed
            }
        }

        guard let image = CGDisplayCreateImage(displayID) else {
            if !hadPermissionBeforeRequest {
                throw ScreenshotError.permissionDenied
            }

            throw ScreenshotError.captureFailed
        }

        return image
    }

    @available(macOS 14.0, *)
    private static func captureImageWithScreenCaptureKit(displayID: CGDirectDisplayID) async throws -> CGImage {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenshotError.captureFailed
        }

        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let excludedApplications = content.applications.filter { application in
            application.processID == currentProcessID
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
        if #available(macOS 14.2, *) {
            filter.includeMenuBar = true
        }

        let configuration = SCStreamConfiguration()
        configuration.width = CGDisplayPixelsWide(displayID)
        configuration.height = CGDisplayPixelsHigh(displayID)
        configuration.showsCursor = false
        configuration.captureResolution = .best

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    private static func cursorImageLocation(
        mouseLocation: CGPoint,
        displayID: CGDirectDisplayID,
        image: CGImage
    ) -> CGPoint? {
        guard let screen = NSScreen.screens.first(where: { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }) else {
            return nil
        }

        guard screen.frame.contains(mouseLocation) else {
            return nil
        }

        let scaleX = CGFloat(image.width) / screen.frame.width
        let scaleY = CGFloat(image.height) / screen.frame.height
        let x = (mouseLocation.x - screen.frame.minX) * scaleX
        let yFromTop = (screen.frame.maxY - mouseLocation.y) * scaleY

        return CGPoint(x: x, y: yFromTop)
    }

    private static func drawCursorMarker(on image: CGImage, cursorImageLocation: CGPoint?) -> CGImage? {
        guard let cursorImageLocation else {
            return image
        }

        let imageSize = NSSize(width: image.width, height: image.height)
        let markerLocation = CGPoint(
            x: cursorImageLocation.x,
            y: CGFloat(image.height) - cursorImageLocation.y
        )
        let outputImage = NSImage(size: imageSize)
        outputImage.lockFocus()
        defer { outputImage.unlockFocus() }

        NSImage(cgImage: image, size: imageSize).draw(
            in: NSRect(origin: .zero, size: imageSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )

        let markerRadius: CGFloat = 34
        let markerRect = NSRect(
            x: markerLocation.x - markerRadius,
            y: markerLocation.y - markerRadius,
            width: markerRadius * 2,
            height: markerRadius * 2
        )

        NSColor.systemRed.setStroke()
        let circle = NSBezierPath(ovalIn: markerRect)
        circle.lineWidth = 6
        circle.stroke()

        let horizontalLine = NSBezierPath()
        horizontalLine.move(to: CGPoint(x: markerLocation.x - markerRadius * 1.4, y: markerLocation.y))
        horizontalLine.line(to: CGPoint(x: markerLocation.x + markerRadius * 1.4, y: markerLocation.y))
        horizontalLine.lineWidth = 5
        horizontalLine.stroke()

        let verticalLine = NSBezierPath()
        verticalLine.move(to: CGPoint(x: markerLocation.x, y: markerLocation.y - markerRadius * 1.4))
        verticalLine.line(to: CGPoint(x: markerLocation.x, y: markerLocation.y + markerRadius * 1.4))
        verticalLine.lineWidth = 5
        verticalLine.stroke()

        guard let tiffData = outputImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.cgImage
    }

    private static func frontmostWindowTitle(processIdentifier: pid_t?) -> String? {
        guard let processIdentifier else { return nil }
        guard
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else {
            return nil
        }

        return windows.first { window in
            guard
                let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                let layer = window[kCGWindowLayer as String] as? Int
            else {
                return false
            }

            return ownerPID == processIdentifier && layer == 0
        }?[kCGWindowName as String] as? String
    }
}

enum ScreenshotError: LocalizedError, Equatable {
    case permissionDenied
    case captureFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Sasu still cannot capture the screen. If Screen Recording is already enabled for Sasu, relaunch Sasu so macOS applies the new permission."
        case .captureFailed:
            return "Sasu could not capture the main display."
        case .encodingFailed:
            return "Sasu captured the display but could not encode the screenshot."
        }
    }
}
