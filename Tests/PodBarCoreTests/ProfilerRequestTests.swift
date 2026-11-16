import XCTest
@testable import PodBarCore

final class ProfilerRequestTests: XCTestCase {
    func testSuccessfulProcessOutput() throws {
        let request = ProfilerRequest(executable: "/usr/bin/printf", arguments: ["hello"], timeout: 2)
        XCTAssertEqual(String(data: try request.readData(), encoding: .utf8), "hello")
    }

    func testFailureExitCode() {
        let request = ProfilerRequest(executable: "/usr/bin/false", arguments: [], timeout: 2)
        XCTAssertThrowsError(try request.readData()) { XCTAssertEqual($0 as? ProfilerError, .failed(1)) }
    }

    func testTimeoutActuallyStopsProcess() {
        let start = Date()
        let request = ProfilerRequest(executable: "/bin/sleep", arguments: ["30"], timeout: 0.1)
        XCTAssertThrowsError(try request.readData()) { XCTAssertEqual($0 as? ProfilerError, .timedOut) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testCancellationBeforeLaunch() {
        let request = ProfilerRequest(executable: "/bin/sleep", arguments: ["30"])
        request.cancel()
        XCTAssertThrowsError(try request.readData()) { XCTAssertEqual($0 as? ProfilerError, .cancelled) }
    }

    func testCancellationDuringRead() {
        let request = ProfilerRequest(executable: "/bin/sleep", arguments: ["30"])
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { request.cancel() }
        let start = Date()
        XCTAssertThrowsError(try request.readData()) { XCTAssertEqual($0 as? ProfilerError, .cancelled) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
}
