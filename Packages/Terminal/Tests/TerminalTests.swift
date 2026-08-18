@testable import Terminal
import XCTest

final class PreCancelledSignal: TerminalCancellationToken {
    let isCancelled = true
}

final class TerminalTests: XCTestCase {
    let runner = TerminalRunner()

    func testEchoStdout() async throws {
        let r = try await runner.run("echo hello-terminal")
        XCTAssertEqual(r.terminationStatus, 0)
        XCTAssertFalse(r.timedOut)
        XCTAssertFalse(r.cancelled)
        XCTAssertTrue(r.stdout.contains("hello-terminal"))
        XCTAssertTrue(r.displayString(maxCharacters: 500).contains("退出码 0"))
    }

    func testStderrCapture() async throws {
        let r = try await runner.run("echo boom 1>&2")
        XCTAssertTrue(r.stderr.contains("boom"))
        XCTAssertTrue(r.combinedOutput.contains("[stderr]"))
    }

    func testNonZeroExitCode() async throws {
        let r = try await runner.run("exit 3")
        XCTAssertEqual(r.terminationStatus, 3)
        XCTAssertTrue(r.combinedOutput.contains("（无输出）"))
    }

    func testTimeoutTerminates() async throws {
        let cfg = TerminalConfiguration(timeout: 0.3)
        let r = try await TerminalRunner(configuration: cfg).run("sleep 10")
        XCTAssertTrue(r.timedOut)
        XCTAssertLessThan(r.duration, 5)
        XCTAssertTrue(r.displayString(maxCharacters: 200).contains("超时被终止"))
    }

    func testPreCancelledSignalReturnsImmediately() async throws {
        let start = Date()
        let r = try await runner.run("sleep 10", signal: PreCancelledSignal())
        XCTAssertTrue(r.cancelled)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    func testWorkingDirectory() async throws {
        let r = try await runner.run("pwd", signal: nil)
        var cfg = TerminalConfiguration()
        cfg.workingDirectory = "/tmp"
        let inTmp = try await TerminalRunner(configuration: cfg).run("pwd")
        XCTAssertTrue(inTmp.stdout.trimmingCharacters(in: .whitespaces).contains("tmp")) // macOS /tmp -> /private/tmp
        _ = r
    }

    func testEnvironmentOverride() async throws {
        var cfg = TerminalConfiguration()
        cfg.environment = ["HARNESS_TEST_VAR": "abc123"]
        let r = try await TerminalRunner(configuration: cfg).run("printenv HARNESS_TEST_VAR")
        XCTAssertTrue(r.stdout.contains("abc123"))
    }

    func testOutputTruncation() async throws {
        let cfg = TerminalConfiguration(maxOutputCharacters: 200)
        _ = cfg
        let r = try await runner.run("yes | head -c 5000")
        XCTAssertEqual(r.displayString(maxCharacters: 200).count, 200)
    }

    func testCaptureByteLimit() async throws {
        let cfg = TerminalConfiguration(timeout: 1, maxCaptureBytes: 1000)
        let r = try await TerminalRunner(configuration: cfg).run("yes | head -c 100000")
        // 捕获上限生效：不管命令输出多大，最多保留 maxCaptureBytes
        XCTAssertLessThanOrEqual(r.stdout.utf8.count, 1000)
    }

    func testLaunchFailed() async throws {
        let cfg = TerminalConfiguration(shellPath: "/nonexistent/shell")
        _ = cfg
        let bad = TerminalRunner(configuration: cfg)
        do {
            _ = try await bad.run("echo hi")
            XCTFail("应当抛出 launchFailed")
        } catch let TerminalError.launchFailed(reason) {
            XCTAssertFalse(reason.isEmpty)
        }
    }
}
