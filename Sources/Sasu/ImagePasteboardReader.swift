import AppKit
import UniformTypeIdentifiers

enum ImagePasteboardReader {
    static func imageData(from pasteboard: NSPasteboard) -> Data? {
        if let fileData = imageFileData(from: pasteboard) {
            return fileData
        }

        let typeCandidates: [NSPasteboard.PasteboardType] = [
            .png,
            .tiff,
            NSPasteboard.PasteboardType(UTType.jpeg.identifier),
            NSPasteboard.PasteboardType(UTType.webP.identifier),
            NSPasteboard.PasteboardType(UTType.heic.identifier),
            NSPasteboard.PasteboardType(UTType.image.identifier)
        ]
        for pasteboardType in typeCandidates {
            if let data = pasteboard.data(forType: pasteboardType),
               NSImage(data: data) != nil {
                return data
            }
        }

        guard let image = NSImage(pasteboard: pasteboard),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return nil
        }

        return pngData
    }

    private static func imageFileData(from pasteboard: NSPasteboard) -> Data? {
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return nil
        }

        for url in urls {
            let accessedSecurityScopedResource = url.startAccessingSecurityScopedResource()
            defer {
                if accessedSecurityScopedResource {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            if let data = try? Data(contentsOf: url), NSImage(data: data) != nil {
                return data
            }
        }

        return nil
    }
}
