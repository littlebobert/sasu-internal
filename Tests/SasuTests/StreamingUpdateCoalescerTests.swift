import XCTest
@testable import Sasu

@MainActor
final class StreamingUpdateCoalescerTests: XCTestCase {
    func testBurstDeliversOnlyLatestValue() async {
        var deliveredValues: [String] = []
        let coalescer = StreamingUpdateCoalescer<String>(interval: .milliseconds(20)) { value in
            deliveredValues.append(value)
        }

        coalescer.submit("first")
        coalescer.submit("second")
        coalescer.submit("latest")

        try? await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(deliveredValues, ["latest"])
    }

    func testFlushImmediatelyDeliversLatestValue() {
        var deliveredValues: [String] = []
        let coalescer = StreamingUpdateCoalescer<String>(interval: .seconds(1)) { value in
            deliveredValues.append(value)
        }

        coalescer.submit("first")
        coalescer.submit("latest")
        coalescer.flush()

        XCTAssertEqual(deliveredValues, ["latest"])
    }

    func testCancelDiscardsPendingValue() async {
        var deliveredValues: [String] = []
        let coalescer = StreamingUpdateCoalescer<String>(interval: .milliseconds(20)) { value in
            deliveredValues.append(value)
        }

        coalescer.submit("stale")
        coalescer.cancel()

        try? await Task.sleep(for: .milliseconds(60))

        XCTAssertTrue(deliveredValues.isEmpty)
    }
}
