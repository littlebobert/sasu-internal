import Foundation

enum TextSpacingRepair {
    static func repairMissingSpaces(in text: String) -> String {
        var repairedText = text

        [
            (#"([.!?])(?=(?:[*_~`]+)?[A-Z])"#, "$1 "),
            (#"(:)(?=(?:[*_~`]+)?(?:https?://|[A-Z]))"#, "$1 "),
            (#"(\))(?=(?:[*_~`]+)?[A-Z])"#, "$1 "),
            (#"(\.(?:jp|com|org|net|io|dev|app|ai))(?=(?:[*_~`]+)?[A-Z])"#, "$1 "),
            (#"(\.(?:html?|php|aspx))(?=(?:[*_~`]+)?[A-Z])"#, "$1 "),
            (#"(\.(?:jp|com|org|net|io|dev|app|ai|html?|php|aspx))(?=(?:[Ii]nto|[Tt]o|[Ii]f|[Dd]o|[Kk]eep|[Aa]lso|[Tt]hey|[Nn]ow))"#, "$1 "),
            (#"\b([Ii]nto|[Tt]o)(?=https?://)"#, "$1 "),
            (#"([a-z0-9])(?=\*(?!\*))"#, "$1 "),
            (#"(?<!\*)\*(?=[A-Z])"#, "* ")
        ].forEach { pattern, replacement in
            repairedText = repairedText.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }

        return repairedText
    }
}
