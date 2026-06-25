import AppKit
import Foundation

struct PasteboardBackup {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(items: [[NSPasteboard.PasteboardType: Data]] = []) {
        self.items = items
    }

    static func capture(from pasteboard: NSPasteboard = .general) -> PasteboardBackup {
        let items: [[NSPasteboard.PasteboardType: Data]] = pasteboard.pasteboardItems?.map { item in
            var itemData: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    itemData[type] = data
                }
            }
            return itemData
        } ?? []

        return PasteboardBackup(items: items)
    }

    func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()

        guard !items.isEmpty else { return }

        let pasteboardItems = items.map { itemData -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            return item
        }

        pasteboard.writeObjects(pasteboardItems)
    }
}
