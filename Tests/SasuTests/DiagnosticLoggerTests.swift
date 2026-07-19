import XCTest
@testable import Sasu

final class DiagnosticLoggerTests: XCTestCase {
    func testBugReportRedactsRequestContentAndDropsContinuationLines() {
        let log = """
        2026-07-19T10:00:00.000Z [OpenAI] prompt=Translate this private text
        {"answer":"Private translation"}
        2026-07-19T10:00:01.000Z [Safari] Safari page capture ready. title=Private page characters=100
        2026-07-19T10:00:02.000Z [OpenAI] Clipboard translation ready. sourceCharacters=20
        """

        let sanitized = DiagnosticLogger.sanitizedLogTextForBugReport(log)

        XCTAssertFalse(sanitized.contains("private text"))
        XCTAssertFalse(sanitized.contains("Private translation"))
        XCTAssertFalse(sanitized.contains("Private page"))
        XCTAssertFalse(sanitized.contains(#"{"answer""#))
        XCTAssertTrue(sanitized.contains("Request content redacted for privacy."))
        XCTAssertTrue(sanitized.contains("Clipboard translation ready. sourceCharacters=20"))
    }

    func testBugReportDropsUnstructuredLegacyLogContent() {
        let sanitized = DiagnosticLogger.sanitizedLogTextForBugReport(
            "Unstructured translation request that predates safe logging"
        )

        XCTAssertEqual(sanitized, "")
    }
}
