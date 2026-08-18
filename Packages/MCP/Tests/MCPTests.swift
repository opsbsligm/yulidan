@testable import MCP
import Session
import Tools
import XCTest

final class MCPTests: XCTestCase {
    func context() -> ToolRunContext {
        ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
    }

    private func makeClient() async -> MockMCPClient {
        let client = MockMCPClient(name: "mock")
        await client.addTool(MCPToolSpec(name: "greet", description: "问候", inputSchema: "{\"name\": \"名字\"}")) { args in
            "你好，\(args["name"] ?? "陌生人")"
        }
        await client.addTool(MCPToolSpec(name: "boom", description: "抛错")) { _ in
            throw MCPError.serverFailed("内部爆炸")
        }
        return client
    }

    func testMockListTools() async throws {
        let client = MockMCPClient(name: "mock")
        await client.addTool(MCPToolSpec(name: "a", description: "工具A")) { _ in "A" }
        let tools = try await client.listTools()
        XCTAssertEqual(tools.map(\.name), ["a"])
    }

    func testMockCallTool() async throws {
        let client = await makeClient()
        let out = try await client.callTool(name: "greet", arguments: ["name": "Harness"])
        XCTAssertEqual(out, "你好，Harness")
    }

    func testMockUnknownToolThrows() async throws {
        let client = await makeClient()
        do {
            _ = try await client.callTool(name: "nope", arguments: [:])
            XCTFail("应当抛出 unknownTool")
        } catch let MCPError.unknownTool(name) {
            XCTAssertEqual(name, "nope")
        }
    }

    func testAdapterExecute() async throws {
        let client = await makeClient()
        let spec = MCPToolSpec(name: "greet", description: "问候")
        let tool = MCPToolAdapter(client: client, spec: spec)
        XCTAssertEqual(tool.name, "mcp_mock_greet")
        let res = try await tool.execute(["name": "UI"], context: context())
        XCTAssertNil(res.error)
        XCTAssertEqual(res.meta?["server"], "mock")
        let text = res.content.first.flatMap {
            if case let .text(t) = $0 {
                return t
            }
            return nil
        } ?? ""
        XCTAssertTrue(text.contains("你好"))
    }

    func testAdapterServerErrorReturnsToolError() async throws {
        let client = await makeClient()
        let tool = MCPToolAdapter(client: client, spec: MCPToolSpec(name: "boom", description: "抛错"))
        let res = try await tool.execute(["name": "x"], context: context())
        XCTAssertEqual(res.error?.code, "mcp_call_failed")
    }

    func testManagerMakeToolsEndToEnd() async throws {
        let manager = MCPServerManager()
        let client = await makeClient()
        await manager.register(client, descriptor: MCPServer(name: "mock", transport: "in-memory"))
        let servers = await manager.servers()
        XCTAssertEqual(servers.count, 1)

        let tools = await manager.makeTools()
        XCTAssertEqual(tools.count, 2) // greet + boom
        guard let greet = tools.first(where: { $0.name == "mcp_mock_greet" }) else {
            return XCTFail("mcp_mock_greet 未找到")
        }
        let res = try await greet.execute(["name": "Agent"], context: context())
        XCTAssertNil(res.error)
    }

    func testManagerUnregister() async {
        let manager = MCPServerManager()
        let client = await makeClient()
        await manager.register(client)
        await manager.unregister(name: "mock")
        let remaining = await manager.servers()
        let remainingTools = await manager.makeTools()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(remainingTools.isEmpty)
    }

    func testMCPErrorDescriptions() {
        XCTAssertTrue(MCPError.unknownTool("t").description.contains("t"))
        XCTAssertTrue(MCPError.unknownClient("c").description.contains("c"))
        XCTAssertTrue(MCPError.serverFailed("r").description.contains("r"))
        XCTAssertTrue(MCPError.serverError(code: 42, message: "m").description.contains("42"))
        XCTAssertTrue(MCPError.requestTimeout("10s 未响应").description.contains("10s"))
        XCTAssertTrue(MCPError.protocolViolation("p").description.contains("p"))
        XCTAssertEqual(MCPError.transportClosed.description, "MCP 传输已断开")
        XCTAssertTrue(MCPError.launchFailed("l").description.contains("l"))
    }

    func testAdapterCancelledContextReturnsCancelled() async throws {
        let client = await makeClient()
        let tool = MCPToolAdapter(client: client, spec: MCPToolSpec(name: "greet", description: "问候"))
        let signal = CancellationToken()
        signal.cancel()
        let res = try await tool.execute(["name": "A"],
                                         context: ToolRunContext(signal: signal, sessionID: SessionID(), metadata: [:]))
        XCTAssertEqual(res.error?.code, "cancelled")
    }

    func testMakeToolsSkipsFailingClient() async {
        let manager = MCPServerManager()
        let good = await makeClient()
        await manager.register(good)
        let bad = StdioMCPClient(name: "bad",
                                 configuration: StdioMCPConfiguration(command: "/nonexistent-mcp-\(UUID().uuidString)", arguments: []))
        await manager.register(bad)
        // 坏客户端 listTools 失败被跳过，不影响好客户端
        let tools = await manager.makeTools()
        XCTAssertEqual(tools.map(\.name).sorted(), ["mcp_mock_boom", "mcp_mock_greet"])
        await manager.unregister(name: "bad")
    }
}

// MARK: - StdioMCPClient（真实子进程 + NDJSON JSON-RPC 2.0）

/// 内嵌假 MCP 服务器（python3，stdio NDJSON）
private let fakeMCPServerSource = #"""
import json, sys, time


def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()
    with open("/tmp/fake-mcp-server.log", "a") as log:
        log.write("SENT-TO-STDOUT %s\n" % type(sys.stdout))
        log.flush()


def main():
    import os
    with open("/tmp/fake-mcp-server.log", "a") as log:
        st = os.fstat(1)
        log.write("server-start pid=%d fd1-ispipe=%s\n" % (os.getpid(), (st.st_mode & 0o170000) == 0o010000))
        log.flush()
    while True:
        line = sys.stdin.readline()
        if not line:
            break
        with open("/tmp/fake-mcp-server.log", "a") as log:
            log.write("GOT: %r\n" % line)
            log.flush()
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except Exception:
            continue
        mid = msg.get("id")
        method = msg.get("method")
        params = msg.get("params") or {}
        if method == "initialize":
            send({"jsonrpc": "2.0", "id": mid, "result": {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}}, "serverInfo": {"name": "fake-mcp", "version": "0.0.1"}}})
        elif method == "tools/list":
            tools = [
                {"name": "echo", "description": "echo text", "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}}},
                {"name": "add", "description": "a+b", "inputSchema": {"type": "object"}},
                {"name": "fail", "description": "always errors", "inputSchema": {"type": "object"}},
                {"name": "sleep", "description": "sleep N seconds", "inputSchema": {"type": "object"}},
            ]
            send({"jsonrpc": "2.0", "id": mid, "result": {"tools": tools}})
        elif method == "tools/call":
            name = params.get("name")
            args = params.get("arguments") or {}
            if name == "echo":
                send({"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": "echo: " + str(args.get("text", ""))}]}})
            elif name == "add":
                total = float(args.get("a", 0)) + float(args.get("b", 0))
                send({"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": str(total)}]}})
            elif name == "fail":
                send({"jsonrpc": "2.0", "id": mid, "result": {"isError": True, "content": [{"type": "text", "text": "tool internal error"}]}})
            elif name == "sleep":
                time.sleep(float(args.get("seconds", 5)))
                send({"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": "woke"}]}})
            else:
                send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "unknown tool: " + str(name)}})
        elif method == "shutdown":
            send({"jsonrpc": "2.0", "id": mid, "result": None})


main()
"""#

final class StdioMCPClientTests: XCTestCase {
    private func writeServerScript() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-mcp-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("fake_server.py").path
        try fakeMCPServerSource.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func makeClient(scriptPath: String, requestTimeout: TimeInterval = 10) -> StdioMCPClient {
        let config = StdioMCPConfiguration(
            command: "/usr/bin/env",
            arguments: ["python3", scriptPath],
            requestTimeout: requestTimeout,
            startupTimeout: 10
        )
        return StdioMCPClient(name: "fake", configuration: config)
    }

    func testStdioListToolsAndCallTool() async throws {
        let script = try writeServerScript()
        let client = makeClient(scriptPath: script)
        defer {
            try? FileManager.default.removeItem(atPath: script)
        }
        let tools = try await client.listTools()
        XCTAssertEqual(tools.map(\.name).sorted(), ["add", "echo", "fail", "sleep"])
        let echo = try await client.callTool(name: "echo", arguments: ["text": "harness"])
        XCTAssertEqual(echo, "echo: harness")
        let add = try await client.callTool(name: "add", arguments: ["a": "1.5", "b": "2.25"])
        XCTAssertEqual(add, "3.75")
        await client.stop()
    }

    func testStdioServerIsErrorThrows() async throws {
        let script = try writeServerScript()
        let client = makeClient(scriptPath: script)
        do {
            _ = try await client.callTool(name: "fail", arguments: [:])
            XCTFail("应当抛出 serverError")
        } catch let MCPError.serverError(code, message) {
            XCTAssertEqual(code, -1)
            XCTAssertEqual(message, "tool internal error")
        }
        await client.stop()
    }

    func testStdioUnknownToolThrows() async throws {
        let script = try writeServerScript()
        let client = makeClient(scriptPath: script)
        do {
            _ = try await client.callTool(name: "nope", arguments: [:])
            XCTFail("应当抛出 serverError(-32601)")
        } catch let MCPError.serverError(code, _) {
            XCTAssertEqual(code, -32601)
        }
        await client.stop()
    }

    func testStdioLaunchFailed() async {
        let config = StdioMCPConfiguration(command: "/nonexistent/mcp-server", arguments: [])
        let client = StdioMCPClient(name: "bad", configuration: config)
        do {
            _ = try await client.listTools()
            XCTFail("应当抛出 launchFailed")
        } catch let MCPError.launchFailed(reason) {
            XCTAssertFalse(reason.isEmpty)
        } catch {
            XCTFail("错误类型不符：\(error)")
        }
    }

    func testStdioStopFailsPendingRequests() async throws {
        let script = try writeServerScript()
        let client = makeClient(scriptPath: script, requestTimeout: 30)
        _ = try await client.listTools()
        let task = Task {
            try await client.callTool(name: "sleep", arguments: ["seconds": "10"])
        }
        try await Task.sleep(nanoseconds: 500_000_000)
        await client.stop()
        do {
            _ = try await task.value
            XCTFail("应当抛出 transportClosed")
        } catch let MCPError.transportClosed {
            // 预期
        } catch {
            XCTFail("错误类型不符：\(error)")
        }
    }

    func testStdioRequestTimeout() async throws {
        let script = try writeServerScript()
        let client = makeClient(scriptPath: script, requestTimeout: 1)
        _ = try await client.listTools()
        do {
            _ = try await client.callTool(name: "sleep", arguments: ["seconds": "1.5"])
            XCTFail("应当抛出 requestTimeout")
        } catch let MCPError.requestTimeout(reason) {
            XCTAssertFalse(reason.isEmpty)
        } catch {
            XCTFail("错误类型不符：\(error)")
        }
        // 假服务器串行处理：等它完成上一个 sleep 请求后，再验证客户端仍可用
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let echo = try await client.callTool(name: "echo", arguments: ["text": "again"])
        XCTAssertEqual(echo, "echo: again")
        await client.stop()
    }
}

// MARK: - 怪癖服务器（stderr / 垃圾行 / 无 result 响应 / null result）

/// 内嵌怪癖 MCP 服务器（python3，stdio NDJSON）
private let quirkyMCPServerSource = #"""
import json, sys


def main():
    sys.stderr.write("quirky boot\n")
    sys.stderr.flush()
    while True:
        line = sys.stdin.readline()
        if not line:
            break
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except Exception:
            continue
        mid = msg.get("id")
        method = msg.get("method")
        if method == "initialize":
            init_result = {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}},
                           "serverInfo": {"name": "quirky", "version": "0.0.1"}}
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid, "result": init_result}) + "\n")
            sys.stdout.flush()
        elif method == "tools/list":
            tools = [
                {"name": "ghost", "description": "responds without result", "inputSchema": {"type": "object"}},
                {"name": "nulltool", "description": "null result", "inputSchema": {"type": "object"}},
            ]
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid, "result": {"tools": tools}}) + "\n")
            sys.stdout.write("garbage line not json\n")
            sys.stdout.flush()
        elif method == "tools/call":
            name = (msg.get("params") or {}).get("name")
            if name == "ghost":
                sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid}) + "\n")
                sys.stdout.flush()
            elif name == "nulltool":
                sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid, "result": None}) + "\n")
                sys.stdout.flush()


main()
"""#

final class QuirkyMCPServerTests: XCTestCase {
    func testQuirks() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-mcp-quirky-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: dir)
        }
        let script = dir.appendingPathComponent("quirky_server.py").path
        try quirkyMCPServerSource.write(toFile: script, atomically: true, encoding: .utf8)
        let config = StdioMCPConfiguration(command: "/usr/bin/env",
                                           arguments: ["python3", script],
                                           requestTimeout: 10,
                                           startupTimeout: 10)
        let client = StdioMCPClient(name: "quirky", configuration: config)
        // 垃圾行被忽略，tools/list 正常
        let tools = try await client.listTools()
        XCTAssertEqual(tools.map(\.name).sorted(), ["ghost", "nulltool"])
        // 无 result 的响应 → protocolViolation
        do {
            _ = try await client.callTool(name: "ghost", arguments: [:])
            XCTFail("应当抛出 protocolViolation")
        } catch let MCPError.protocolViolation(reason) {
            XCTAssertFalse(reason.isEmpty)
        } catch {
            XCTFail("错误类型不符：\(error)")
        }
        // null result → 空文本
        let out = try await client.callTool(name: "nulltool", arguments: [:])
        XCTAssertEqual(out, "")
        // stderr 诊断
        try await Task.sleep(nanoseconds: 300_000_000)
        let stderr = await client.recentStderr
        XCTAssertTrue(stderr.contains("quirky boot"))
        await client.stop()
    }
}
