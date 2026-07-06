import Foundation

struct BrowserPageContext: Equatable {
    let browserName: String
    let pageTitle: String
    let pageURL: String
    let text: String
    let originalCharacterCount: Int
    let isTruncated: Bool

    var displayTitle: String {
        if !pageTitle.isEmpty {
            return pageTitle
        }

        return pageURL.isEmpty ? "Current page" : pageURL
    }
}
