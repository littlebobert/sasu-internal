import AppKit
import XCTest
@testable import Sasu

final class ImportedImageTests: XCTestCase {
    func testImportedImageBuildsPayloadAndUploadImage() throws {
        let image = NSImage(size: NSSize(width: 40, height: 24))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 24).fill()
        image.unlockFocus()

        let payload = try ScreenshotPayload.importedImage(from: image)
        XCTAssertEqual(payload.source, .importedImage)
        XCTAssertTrue(payload.isImportedImage)
        XCTAssertNil(payload.cursorImageLocation)
        XCTAssertNil(payload.browserPageContext)
        XCTAssertGreaterThan(payload.pngData.count, 0)
        XCTAssertEqual(Int(payload.pixelSize.width), 40)
        XCTAssertEqual(Int(payload.pixelSize.height), 24)

        let upload = try payload.uploadImage
        XCTAssertEqual(upload.mimeType, "image/jpeg")
        XCTAssertGreaterThan(upload.data.count, 0)
        XCTAssertNil(upload.cursorImageLocation)
    }

    func testImportedImagePromptOmitsCursorMarker() throws {
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 20, height: 20).fill()
        image.unlockFocus()

        let payload = try ScreenshotPayload.importedImage(from: image)
        let prompt = try AIRequestSupport.buildScreenshotPrompt(
            prompt: "Translate this",
            screenshot: payload,
            translationSourceLanguage: .japanese,
            conversationContext: nil
        )

        XCTAssertTrue(prompt.contains("Image context:"))
        XCTAssertTrue(prompt.contains("dropped or imported"))
        XCTAssertFalse(prompt.contains("red crosshair"))
        XCTAssertFalse(prompt.contains("Frontmost app:"))
    }

    func testInvalidImageDataThrows() {
        XCTAssertThrowsError(try ScreenshotPayload.importedImage(from: Data([0x00, 0x01, 0x02]))) { error in
            XCTAssertEqual(error as? ScreenshotError, .invalidImage)
        }
    }
}
