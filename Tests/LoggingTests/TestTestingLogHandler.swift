@testable import Logging
import XCTest

final class TestTestingLogHandler: XCTestCase {

    public func testExample() {
        DelegatedLogHandler.bootstrap { TestingLogHandler(label: $0) }
        do {
            let container = TestingLogHandler.container {
                $0.match(label: "Example", level: .debug)
            }
            XCTAssertEqual(TestingLogHandler.containers.count, 1)

            var example = Logger(label: "Example")
            example.logLevel = .critical
            example.info("Not matched, since info level is different")
            example.debug("Matched")

            var example1 = Logger(label: "Example1")
            example1.logLevel = .debug
            example1.debug("This message should be printed to stderr")

            XCTAssertFalse(container.messages.isEmpty)
            if let first = container.messages.first {
                XCTAssertEqual(first.message.description, "Matched")
                XCTAssertTrue(
                    try first.description.contains(Regex(
                        "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}.\\d+Z debug Example : \\[LoggingTests\\] Matched$"
                    )),
                    "message format, not as expected: \(first.description)"
                )
            }
        }

        // Ensure weak ref works correctly:
        XCTAssertEqual(TestingLogHandler.containers.count, 0)
        DelegatedLogHandler.bootstrap({ StreamLogHandler.standardError(label: $0) })
    }
}