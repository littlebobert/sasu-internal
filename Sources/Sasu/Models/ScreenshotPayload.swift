import AppKit
import CoreGraphics
import Foundation

enum ScreenshotSource: Equatable {
    case screenCapture
    case importedImage
}

struct ScreenshotPayload {
    let pngData: Data
    let displayID: CGDirectDisplayID
    let pixelSize: CGSize
    let frontmostApplicationName: String?
    let frontmostApplicationBundleIdentifier: String?
    let frontmostWindowTitle: String?
    let mouseLocation: CGPoint
    let cursorImageLocation: CGPoint?
    let hasVisibleSafariWindow: Bool
    let browserPageContext: BrowserPageContext?
    let browserPageCaptureIssue: String?
    let source: ScreenshotSource

    var isImportedImage: Bool {
        source == .importedImage
    }

    var base64PNG: String {
        pngData.base64EncodedString()
    }

    var uploadImage: UploadImage {
        get throws {
            try UploadImage.make(from: self)
        }
    }

    static func importedImage(from imageData: Data) throws -> ScreenshotPayload {
        guard let image = NSImage(data: imageData) else {
            throw ScreenshotError.invalidImage
        }
        return try importedImage(from: image)
    }

    static func importedImage(from image: NSImage) throws -> ScreenshotPayload {
        guard let pngData = pngData(from: image),
              let pixelSize = pixelSize(of: image),
              pixelSize.width > 0,
              pixelSize.height > 0
        else {
            throw ScreenshotError.invalidImage
        }

        return ScreenshotPayload(
            pngData: pngData,
            displayID: 0,
            pixelSize: pixelSize,
            frontmostApplicationName: nil,
            frontmostApplicationBundleIdentifier: nil,
            frontmostWindowTitle: nil,
            mouseLocation: .zero,
            cursorImageLocation: nil,
            hasVisibleSafariWindow: false,
            browserPageContext: nil,
            browserPageCaptureIssue: nil,
            source: .importedImage
        )
    }

    static func importedImage(contentsOf url: URL) throws -> ScreenshotPayload {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        return try importedImage(from: data)
    }

    func addingBrowserPageContext(_ browserPageContext: BrowserPageContext) -> ScreenshotPayload {
        ScreenshotPayload(
            pngData: pngData,
            displayID: displayID,
            pixelSize: pixelSize,
            frontmostApplicationName: frontmostApplicationName,
            frontmostApplicationBundleIdentifier: frontmostApplicationBundleIdentifier,
            frontmostWindowTitle: frontmostWindowTitle,
            mouseLocation: mouseLocation,
            cursorImageLocation: cursorImageLocation,
            hasVisibleSafariWindow: hasVisibleSafariWindow,
            browserPageContext: browserPageContext,
            browserPageCaptureIssue: nil,
            source: source
        )
    }

    func addingBrowserPageCaptureIssue(_ issue: String) -> ScreenshotPayload {
        ScreenshotPayload(
            pngData: pngData,
            displayID: displayID,
            pixelSize: pixelSize,
            frontmostApplicationName: frontmostApplicationName,
            frontmostApplicationBundleIdentifier: frontmostApplicationBundleIdentifier,
            frontmostWindowTitle: frontmostWindowTitle,
            mouseLocation: mouseLocation,
            cursorImageLocation: cursorImageLocation,
            hasVisibleSafariWindow: hasVisibleSafariWindow,
            browserPageContext: browserPageContext,
            browserPageCaptureIssue: issue,
            source: source
        )
    }

    func removingBrowserPageContext(reason: String) -> ScreenshotPayload {
        ScreenshotPayload(
            pngData: pngData,
            displayID: displayID,
            pixelSize: pixelSize,
            frontmostApplicationName: frontmostApplicationName,
            frontmostApplicationBundleIdentifier: frontmostApplicationBundleIdentifier,
            frontmostWindowTitle: frontmostWindowTitle,
            mouseLocation: mouseLocation,
            cursorImageLocation: cursorImageLocation,
            hasVisibleSafariWindow: hasVisibleSafariWindow,
            browserPageContext: nil,
            browserPageCaptureIssue: reason,
            source: source
        )
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func pixelSize(of image: NSImage) -> CGSize? {
        if let bitmap = image.representations.first as? NSBitmapImageRep {
            return CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
    }
}

struct UploadImage {
    let data: Data
    let mimeType: String
    let pixelSize: CGSize
    let cursorImageLocation: CGPoint?
    let scaleFromOriginal: CGFloat

    var base64DataURL: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    static func make(from screenshot: ScreenshotPayload) throws -> UploadImage {
        let maxDimension: CGFloat = 1800
        let quality: CGFloat = 0.85

        guard let sourceImage = NSImage(data: screenshot.pngData) else {
            throw ScreenshotError.encodingFailed
        }

        let longestSide = max(screenshot.pixelSize.width, screenshot.pixelSize.height)
        let scale = min(1, maxDimension / longestSide)
        let targetPixelSize = CGSize(
            width: floor(screenshot.pixelSize.width * scale),
            height: floor(screenshot.pixelSize.height * scale)
        )

        guard let resizedImage = resize(sourceImage, toPixelSize: targetPixelSize),
              let jpegData = jpegData(from: resizedImage, quality: quality)
        else {
            throw ScreenshotError.encodingFailed
        }

        let cursorLocation = screenshot.cursorImageLocation.map {
            CGPoint(x: $0.x * scale, y: $0.y * scale)
        }

        return UploadImage(
            data: jpegData,
            mimeType: "image/jpeg",
            pixelSize: targetPixelSize,
            cursorImageLocation: cursorLocation,
            scaleFromOriginal: scale
        )
    }

    private static func resize(_ image: NSImage, toPixelSize pixelSize: CGSize) -> NSImage? {
        let outputImage = NSImage(size: pixelSize)
        outputImage.lockFocus()
        defer { outputImage.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: pixelSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )

        return outputImage
    }

    private static func jpegData(from image: NSImage, quality: CGFloat) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        )
    }
}
