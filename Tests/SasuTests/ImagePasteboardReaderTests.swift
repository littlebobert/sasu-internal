import AppKit
import XCTest
@testable import Sasu

final class ImagePasteboardReaderTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
    }

    override func tearDown() {
        pasteboard.clearContents()
        pasteboard = nil
        super.tearDown()
    }

    func testReadsPNGData() throws {
        let pngData = try makeImageData(fileType: .png)
        pasteboard.setData(pngData, forType: .png)

        XCTAssertEqual(ImagePasteboardReader.imageData(from: pasteboard), pngData)
    }

    func testReadsTIFFData() throws {
        let tiffData = try makeImageData(fileType: .tiff)
        pasteboard.setData(tiffData, forType: .tiff)

        XCTAssertEqual(ImagePasteboardReader.imageData(from: pasteboard), tiffData)
    }

    func testReturnsNilForTextOnlyPasteboard() {
        pasteboard.setString("ordinary text", forType: .string)

        XCTAssertNil(ImagePasteboardReader.imageData(from: pasteboard))
    }

    private func makeImageData(fileType: NSBitmapImageRep.FileType) throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let data = bitmap.representation(using: fileType, properties: [:]) else {
            throw TestError.imageEncodingFailed
        }

        return data
    }

    private enum TestError: Error {
        case imageEncodingFailed
    }
}
