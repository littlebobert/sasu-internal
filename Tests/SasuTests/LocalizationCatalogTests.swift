import Foundation
import XCTest
@testable import Sasu

final class LocalizationCatalogTests: XCTestCase {
    private let supportedLanguages = ["ja", "zh-Hans", "zh-Hant"]

    func testEveryUILocalizationHasCompleteTranslationsAndMatchingPlaceholders() throws {
        let catalog = try loadCatalog(named: "Localizable")
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        XCTAssertGreaterThan(strings.count, 150)

        for (key, rawEntry) in strings {
            let entry = try XCTUnwrap(rawEntry as? [String: Any], key)
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any],
                "Missing localizations for \(key)"
            )

            for language in supportedLanguages {
                let value = try localizedValue(
                    for: language,
                    in: localizations,
                    key: key
                )
                XCTAssertFalse(value.isEmpty, "Empty \(language) translation for \(key)")
                XCTAssertEqual(
                    placeholders(in: value),
                    placeholders(in: key),
                    "Placeholder mismatch in \(language) translation for \(key)"
                )
            }
        }
    }

    func testStaticLocalizedSourceKeysAreCataloged() throws {
        let catalog = try loadCatalog(named: "Localizable")
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let sourceRoot = repositoryRoot.appendingPathComponent("Sources/Sasu")
        let sourceFiles = try FileManager.default.subpathsOfDirectory(atPath: sourceRoot.path)
            .filter { $0.hasSuffix(".swift") }
        let patterns = [
            #"String\(localized:\s*\"((?:[^\"\\]|\\.)*)\""#,
            #"(?:Text|Button|Label|Picker|Toggle|Link|CommandMenu)\(\"((?:[^\"\\]|\\.)*)\""#,
            #"\.help\(\"((?:[^\"\\]|\\.)*)\"\)"#
        ].map { try! NSRegularExpression(pattern: $0) }

        var missing: [String] = []
        for relativePath in sourceFiles {
            let source = try String(
                contentsOf: sourceRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            let range = NSRange(source.startIndex..., in: source)
            for regex in patterns {
                for match in regex.matches(in: source, range: range) {
                    guard let captureRange = Range(match.range(at: 1), in: source) else { continue }
                    let encodedKey = String(source[captureRange])
                    guard !encodedKey.isEmpty, !encodedKey.contains(#"\("#) else { continue }
                    let keyData = try XCTUnwrap("\"\(encodedKey)\"".data(using: .utf8))
                    let key = try JSONDecoder().decode(String.self, from: keyData)
                    if strings[key] == nil {
                        missing.append("\(relativePath): \(key)")
                    }
                }
            }
        }

        XCTAssertEqual(missing, [], "Static UI localization keys missing from catalog")
    }

    func testRepresentativeUISurfacesAreCataloged() throws {
        let catalog = try loadCatalog(named: "Localizable")
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let representativeKeys = [
            "About Sasu",
            "Settings…",
            "Capture & Ask",
            "Choose the language you translate from",
            "Ready. Use %@ for the command wheel.",
            "Sasu Needs Screen Recording",
            "Safari Enhancement",
            "Sasu included extracted Safari page text from below the visible viewport.",
            "OpenAI request failed with HTTP status %lld.%@",
            "%lld characters from %@",
            "Japanese",
            "Simplified Chinese",
            "Traditional Chinese"
        ]

        for key in representativeKeys {
            XCTAssertNotNil(strings[key], "Missing representative localization key: \(key)")
        }
    }

    func testPrivacyDescriptionsExistInEverySupportedLanguage() throws {
        let catalog = try loadCatalog(named: "InfoPlist")
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])

        for key in ["NSAccessibilityUsageDescription", "NSAppleEventsUsageDescription"] {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            for language in ["en"] + supportedLanguages {
                XCTAssertFalse(
                    try localizedValue(for: language, in: localizations, key: key).isEmpty
                )
            }
        }
    }

    func testTranscriptDisplayMetadataDoesNotChangeMachineContext() {
        let source = ChatTranscriptMessage(
            role: .user,
            text: "こんにちは",
            sourceKind: .selection
        )

        XCTAssertEqual(source.machineContextText, "Selected text: こんにちは")
        XCTAssertTrue(source.localizedTranscriptText.hasSuffix("こんにちは"))
        XCTAssertEqual(ChatTranscriptMessage.Role.user.rawValue, "You")
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadCatalog(named name: String) throws -> [String: Any] {
        let url = repositoryRoot
            .appendingPathComponent("AppBundle/Localization")
            .appendingPathComponent("\(name).xcstrings")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    private func localizedValue(
        for language: String,
        in localizations: [String: Any],
        key: String
    ) throws -> String {
        let localization = try XCTUnwrap(
            localizations[language] as? [String: Any],
            "Missing \(language) translation for \(key)"
        )
        let unit = try XCTUnwrap(
            localization["stringUnit"] as? [String: Any],
            "Missing string unit for \(language) translation of \(key)"
        )
        XCTAssertEqual(unit["state"] as? String, "translated")
        return try XCTUnwrap(unit["value"] as? String)
    }

    private func placeholders(in value: String) -> [String] {
        let pattern = #"%(?:(\d+)\$)?(?:lld|ld|llu|lu|d|u|@)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).map { match in
            let matched = Range(match.range, in: value).map { String(value[$0]) } ?? ""
            return matched.replacingOccurrences(
                of: #"%\d+\$"#,
                with: "%",
                options: .regularExpression
            )
        }.sorted()
    }
}
