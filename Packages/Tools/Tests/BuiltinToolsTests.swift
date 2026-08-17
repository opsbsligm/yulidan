import Sandbox
import Session
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
