import Sandbox
import Session
import Terminal
@testable import Tools
import XCTest

/// 内置工具真实执行测试
final class BuiltinToolsTests: XCTestCase {
    // 测试夹具：setUp 中赋值，XCTest 标准模式
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func context() -> ToolRunContext {
        ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
    }

    func testReadWriteFileRoundTrip() async throws {
        let path = dir.appendingPathComponent("hello.txt").path
        let w = WriteFileTool()
        let r1 = try await w.execute(["path": path, "content": "你好，Harness\n"], context: context())
        XCTAssertNil(r1.error)

        let r = ReadFileTool()
        let r2 = try await r.execute(["path": path], context: context())
        XCTAssertNil(r2.error)
        let text2 = r2.content.compactMap { block -> String? in
            if case let .text(t) = block {
                return t
            }
            return nil
        }.joined()
        XCTAssertTrue(text2.contains("你好，Harness"))
    }

    func testReadFileMissing() async throws {
        let r = ReadFileTool()
        let res = try await r.execute(["path": "/nonexistent/path-xyz"], context: context())
        XCTAssertNotNil(res.error)
    }

    func testListFiles() async throws {
        FileManager.default.createFile(atPath: dir.appendingPathComponent("a.txt").path,
                                       contents: Data("a".utf8))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"),
                                                withIntermediateDirectories: true)
        let r = ListFilesTool()
        let res = try await r.execute(["path": dir.path], context: context())
        XCTAssertNil(res.error)
        let text = res.content.first.flatMap {
            if case let .text(t) = $0 {
                return t
            }
            return nil
        } ?? ""
        XCTAssertTrue(text.contains("a.txt"))
        XCTAssertTrue(text.contains("sub"))
    }

    func testExecCommandEcho() async throws {
        let r = ExecCommandTool()
        let res = try await r.execute(["cmd": "echo hello-from-harness"], context: context())
        XCTAssertNil(res.error)
        let text = res.content.first.flatMap {
            if case let .text(t) = $0 {
                return t
            }
            return nil
        } ?? ""
        XCTAssertTrue(text.contains("hello-from-harness"))
        XCTAssertTrue(text.contains("退出码 0"))
    }

    func testExecCommandTimeout() async throws {
        let r = ExecCommandTool()
        let start = Date()
        let res = try await r.execute(["cmd": "sleep 10", "timeout": "2"], context: context())
        let elapsed = Date().timeIntervalSince(start)
        // 超时后 terminate，不应等满 10 秒
        XCTAssertLessThan(elapsed, 8)
        _ = res
    }

    // MARK: - 参数与边界分支

    private func text(_ r: ToolResult) -> String {
        r.content.compactMap { block -> String? in
            if case let .text(t) = block {
                return t
            }
            return nil
        }.joined()
    }

    func testReadFileMissingArg() async throws {
        let res = try await ReadFileTool().execute([:], context: context())
        XCTAssertEqual(res.error?.code, "missing_arg")
    }

    func testReadFileTooLarge() async throws {
        let url = dir.appendingPathComponent("big.bin")
        try Data(count: 201_000).write(to: url)
        let res = try await ReadFileTool().execute(["path": url.path], context: context())
        XCTAssertNil(res.error)
        XCTAssertTrue(text(res).contains("文件过大"))
    }

    func testReadFileNonUTF8() async throws {
        let url = dir.appendingPathComponent("binary.dat")
        try Data([0xFF, 0xFE, 0x00, 0x01, 0xFF]).write(to: url)
        let res = try await ReadFileTool().execute(["path": url.path], context: context())
        XCTAssertNil(res.error)
        XCTAssertTrue(text(res).contains("不是 UTF-8 文本"))
    }

    func testWriteFileMissingArg() async throws {
        let res = try await WriteFileTool().execute(["content": "x"], context: context())
        XCTAssertEqual(res.error?.code, "missing_arg")
    }

    func testWriteFileFailsWhenParentIsFile() async throws {
        let file = dir.appendingPathComponent("plain.txt")
        try Data("x".utf8).write(to: file)
        // 父级是文件 → createDirectory 抛错
        let bad = file.appendingPathComponent("child.txt").path
        let res = try await WriteFileTool().execute(["path": bad, "content": "y"], context: context())
        XCTAssertEqual(res.error?.code, "write_failed")
    }

    func testListFilesMissing() async throws {
        let res = try await ListFilesTool().execute(["path": "/nonexistent-harness-\(UUID().uuidString)"], context: context())
        XCTAssertEqual(res.error?.code, "not_found")
    }

    func testListFilesNotDirectory() async throws {
        let file = dir.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        let res = try await ListFilesTool().execute(["path": file.path], context: context())
        XCTAssertNil(res.error)
        XCTAssertTrue(text(res).contains("不是目录"))
    }

    func testListFilesReadFailed() async throws {
        let locked = dir.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer {
            // 恢复权限再清理
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        }
        let res = try await ListFilesTool().execute(["path": locked.path], context: context())
        XCTAssertEqual(res.error?.code, "read_failed")
    }

    func testSizeStrFormatting() {
        XCTAssertEqual(ListFilesTool.sizeStr(512), "512B")
        XCTAssertEqual(ListFilesTool.sizeStr(2048), "2.0KB")
        XCTAssertEqual(ListFilesTool.sizeStr(2 * 1024 * 1024), "2.0MB")
    }

    func testExecCommandMissingArg() async throws {
        let res = try await ExecCommandTool().execute([:], context: context())
        XCTAssertEqual(res.error?.code, "missing_arg")
    }

    func testExecCommandLaunchFailed() async throws {
        // 指向不存在的 shell → Process.run() 抛错 → exec_failed
        let runner = TerminalRunner(configuration: TerminalConfiguration(shellPath: "/nonexistent-shell-\(UUID().uuidString)"))
        let res = try await ExecCommandTool(runner: runner).execute(["cmd": "echo hi"], context: context())
        XCTAssertEqual(res.error?.code, "exec_failed")
    }
}

/// 沙箱集成：文件工具注入 PathSandbox 后越界路径被拒绝
final class BuiltinToolsSandboxTests: XCTestCase {
    func context() -> ToolRunContext {
        ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
    }

    private func text(_ res: ToolResult) -> String {
        res.content.first.flatMap {
            if case let .text(t) = $0 {
                return t
            }
            return nil
        } ?? ""
    }

    func testWriteFileOutsideSandboxRejected() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("harness-t-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: dir)
        }
        let sandbox = PathSandbox(allowedRoots: [dir.path])
        let tool = WriteFileTool(sandbox: sandbox)
        let res = try await tool.execute(["path": dir.path + "/../evil.txt", "content": "x"], context: context())
        XCTAssertEqual(res.error?.code, "outside_sandbox")
        XCTAssertTrue(text(res).contains("沙箱"))
    }

    func testWriteFileInsideSandboxAllowed() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("harness-t-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: dir)
        }
        let sandbox = PathSandbox(allowedRoots: [dir.path])
        let tool = WriteFileTool(sandbox: sandbox)
        let target = dir.appendingPathComponent("ok.txt").path
        let res = try await tool.execute(["path": target, "content": "hi"], context: context())
        XCTAssertNil(res.error)
        XCTAssertEqual((try? String(contentsOf: URL(fileURLWithPath: target), encoding: .utf8)) ?? "", "hi")
    }

    func testReadFileOutsideSandboxRejected() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("harness-t-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: dir)
        }
        let sandbox = PathSandbox(allowedRoots: [dir.path])
        let tool = ReadFileTool(sandbox: sandbox)
        let res = try await tool.execute(["path": "/etc/hostname"], context: context())
        XCTAssertEqual(res.error?.code, "outside_sandbox")
    }

    func testListFilesOutsideSandboxRejected() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("harness-t-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: dir)
        }
        let sandbox = PathSandbox(allowedRoots: [dir.path])
        let tool = ListFilesTool(sandbox: sandbox)
        let res = try await tool.execute(["path": "/usr"], context: context())
        XCTAssertEqual(res.error?.code, "outside_sandbox")
    }
}

// MARK: - web_fetch（零网络 URLProtocol 桩）

/// 零网络 HTTP 桩：按 handler 返回预设响应，记录最后一次请求
private final class StubWebURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (status: Int, body: String))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        let canned = Self.handler?(request) ?? (status: 599, body: "stub 未配置")
        guard let response = HTTPURLResponse(url: request.url!, statusCode: canned.status,
                                             httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "text/plain; charset=utf-8"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(canned.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeStubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubWebURLProtocol.self]
    return URLSession(configuration: config)
}

final class WebFetchToolTests: XCTestCase {
    private func tool(maxBytes: Int = 512_000) -> WebFetchTool {
        WebFetchTool(session: makeStubSession(), maxBytes: maxBytes, timeout: 5)
    }

    private func context() -> ToolRunContext {
        ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
    }

    private func text(_ r: ToolResult) -> String {
        r.content.compactMap { block -> String? in
            if case let .text(t) = block {
                return t
            }
            return nil
        }.joined()
    }

    override func tearDown() {
        StubWebURLProtocol.handler = nil
        super.tearDown()
    }

    func testMissingUrlArg() async throws {
        let res = try await tool().execute([:], context: context())
        XCTAssertEqual(res.error?.code, "missing_arg")
    }

    func testUnsupportedSchemeRejected() async throws {
        let res = try await tool().execute(["url": "ftp://example.com/x"], context: context())
        XCTAssertEqual(res.error?.code, "bad_url")
        let res2 = try await tool().execute(["url": "file:///etc/hosts"], context: context())
        XCTAssertEqual(res2.error?.code, "bad_url")
    }

    func testSuccessReturnsTextAndMeta() async throws {
        StubWebURLProtocol.handler = { _ in (200, "你好，Harness") }
        let res = try await tool().execute(["url": "https://stub.local/page"], context: context())
        XCTAssertNil(res.error)
        XCTAssertTrue(text(res).contains("你好，Harness"))
        XCTAssertEqual(res.meta?["status"], "200")
        XCTAssertEqual(res.meta?["truncated"], "false")
        // 请求头校验：GET + User-Agent
        let req = StubWebURLProtocol.lastRequest
        XCTAssertEqual(req?.httpMethod, "GET")
        let ua = req?.value(forHTTPHeaderField: "User-Agent") ?? ""
        XCTAssertFalse(ua.isEmpty)
    }

    func testHttpErrorReturnsCode() async throws {
        StubWebURLProtocol.handler = { _ in (404, "not found") }
        let res = try await tool().execute(["url": "https://stub.local/404"], context: context())
        XCTAssertEqual(res.error?.code, "http_error")
        XCTAssertTrue(text(res).contains("404"))
    }

    func testTooLargeRejected() async throws {
        StubWebURLProtocol.handler = { _ in (200, String(repeating: "x", count: 513_000)) }
        let res = try await tool().execute(["url": "https://stub.local/big"], context: context())
        XCTAssertEqual(res.error?.code, "too_large")
    }

    func testMaxCharsTruncation() async throws {
        StubWebURLProtocol.handler = { _ in (200, String(repeating: "字", count: 100)) }
        let res = try await tool().execute(["url": "https://stub.local/long", "max_chars": "10"], context: context())
        XCTAssertNil(res.error)
        XCTAssertEqual(res.meta?["truncated"], "true")
        XCTAssertTrue(text(res).hasSuffix(String(repeating: "字", count: 10)))
    }
}
