import Foundation
import MCP
import Testing
import Tools
import XCTest

// MARK: - 覆盖审计轮 5：MCP 包薄弱分支（manager 非 stdio 路径 / stdio 诊断与防御分支 / 服务发现兜底）

private struct FailingMCPClient: MCPClient {
    let name = "failing-mcp"
    func listTools() async throws -> [MCPToolSpec] {
        throw MCPError.serverFailed("down")
    }

    func callTool(name _: String, arguments _: [String: String]) async throws -> String {
        throw MCPError.serverFailed("down")
    }
}

/// 报告 cwd 的极简假服务器（serverInfo.name = 工作目录）
private let cwdServerSource = #"""
import json, os, sys


def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


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
        send({"jsonrpc": "2.0", "id": mid, "result": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "serverInfo": {"name": os.getcwd(), "version": "1.0"}}})
    elif method == "tools/list":
        send({"jsonrpc": "2.0", "id": mid, "result": {"tools": []}})
    elif method == "ping":
        send({"jsonrpc": "2.0", "id": mid, "result": {}})
"""#

/// 启动时向 stderr 灌 1024 字节的假服务器（验证 stderr 缓冲截断）
private let stderrFloodServerSource = #"""
import json, sys

sys.stderr.write("X" * 1024)
sys.stderr.flush()


def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


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
        send({"jsonrpc": "2.0", "id": mid, "result": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "serverInfo": {"name": "fake-flood", "version": "1.0"}}})
    elif method == "tools/list":
        send({"jsonrpc": "2.0", "id": mid, "result": {"tools": []}})
    elif method == "ping":
        send({"jsonrpc": "2.0", "id": mid, "result": {}})
"""#

/// 服务器 → 客户端请求假服务器（等待应答并原样回传，验证 -32603 错误应答）
private let serverRequestServerSource = #"""
import json, sys


def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


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
        send({"jsonrpc": "2.0", "id": mid, "result": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "serverInfo": {"name": "fake-srvreq", "version": "1.0"}}})
    elif method == "tools/list":
        send({"jsonrpc": "2.0", "id": mid, "result": {"tools": [
            {"name": "server_request", "description": "x", "inputSchema": {"type": "object"}}]}})
    elif method == "tools/call":
        params = msg.get("params") or {}
        if params.get("name") == "server_request":
            send({"jsonrpc": "2.0", "id": 999, "method": "client/echo", "params": {"value": 42}})
            reply = None
            while True:
                rline = sys.stdin.readline()
                if not rline:
                    break
                try:
                    rmsg = json.loads(rline.strip())
                except Exception:
                    continue
                if rmsg.get("id") == 999:
                    reply = rmsg
                    break
            text = json.dumps(reply) if reply is not None else "got-no-reply"
            send({"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": text}]}})
        else:
            send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "unknown tool"}})
"""#

final class MCPGapCoverageTests: XCTestCase {
    private func writeScript(_ source: String, name: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-mcp-gap-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(name).path
        try source.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func makeClient(scriptPath: String,
                            workingDirectory: String? = nil,
                            maxStderrBytes: Int = 4096) -> StdioMCPClient {
        StdioMCPClient(name: "fake", configuration: StdioMCPConfiguration(
            command: "/usr/bin/env",
            arguments: ["python3", scriptPath],
            workingDirectory: workingDirectory,
            requestTimeout: 10,
            startupTimeout: 10,
            maxStderrBytes: maxStderrBytes
        ))
    }

    // MARK: - StdioMCPClient 诊断/防御分支

    // 注：parseCapabilities 为 internal 纯防御解析（非法 JSON → nil），公共 API 不可达，标注不可单测

    /// workingDirectory 配置生效：子进程 cwd = 配置目录（serverInfo.name 回报）
    func testWorkingDirectoryAppliedOnStart() async throws {
        let script = try writeScript(cwdServerSource, name: "cwd_server.py")
        defer { try? FileManager.default.removeItem(atPath: script) }
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-cwd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let client = makeClient(scriptPath: script, workingDirectory: workDir.path)
        defer { Task { await client.stop() } }
        let tools = try await client.listTools() // 成功即完成 start（幂等）+ 握手
        XCTAssertTrue(tools.isEmpty)
        let negotiated = await client.capabilities()
        // 子进程 cwd 为真实路径（/var → /private/var）；realpath 归一化
        // （NSString/URL.resolvingSymlinksInPath 本机不解析 /var 符号链接，已实证）
        var resolved = workDir.path
        let resolvedPtr = realpath(resolved, nil)
        let expectedCwd = resolvedPtr.map { String(cString: $0) } ?? resolved
        XCTAssertEqual(negotiated?.serverName, expectedCwd)
    }

    /// onServerRequest 处理器抛错 → 自动回 -32603（message = 错误描述）
    func testServerRequestHandlerThrowYieldsInternalError() async throws {
        let script = try writeScript(serverRequestServerSource, name: "srvreq_server.py")
        defer { try? FileManager.default.removeItem(atPath: script) }
        let client = makeClient(scriptPath: script)
        defer { Task { await client.stop() } }
        client.onServerRequest = { _, _ in
            throw MCPError.serverError(code: -1, message: "handler boom")
        }
        try await client.start()
        let result = try await client.callTool(name: "server_request", arguments: [:])
        XCTAssertTrue(result.contains("-32603"), "应答应携带 -32603：\(result)")
        // python json.dumps 默认 ensure_ascii，中文会被转义；断言 ASCII 子串
        XCTAssertTrue(result.contains("handler boom"), "应答应携带自定义错误描述：\(result)")
    }

    /// stderr 缓冲截断：灌 1024 字节、上限 64 → recentStderr 恰为末尾 64 字节
    func testStderrTruncatedToMaxBytes() async throws {
        let script = try writeScript(stderrFloodServerSource, name: "flood_server.py")
        defer { try? FileManager.default.removeItem(atPath: script) }
        let client = makeClient(scriptPath: script, maxStderrBytes: 64)
        defer { Task { await client.stop() } }
        try await client.start()
        // 有界轮询等待 stderr 泵读完（避免固定 sleep 时序脆弱）
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if await client.recentStderr.count >= 64 {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let tail = await client.recentStderr
        XCTAssertGreaterThanOrEqual(tail.count, 64)
        XCTAssertLessThanOrEqual(tail.count, 64)
        XCTAssertTrue(tail.allSatisfy { $0 == "X" }, "截断后应为 X 结尾缓冲：\(tail)")
    }

    // MARK: - MCPServerManager 非 stdio 路径

    /// 内存客户端：isConnected 走 descriptor（L343 分支）+ ping 恒真（L352 分支）
    func testIsConnectedAndPingForNonStdioClient() async {
        let manager = MCPServerManager()
        await manager.register(MockMCPClient(name: "mock-mcp"))
        let available = await manager.isConnected(name: "mock-mcp")
        XCTAssertTrue(available)
        let pong = await manager.ping(name: "mock-mcp")
        XCTAssertTrue(pong)
        // 不可用 descriptor → isConnected 透传 false
        await manager.register(MockMCPClient(name: "mock-off"),
                               descriptor: MCPServer(name: "mock-off", transport: "in-memory", isAvailable: false))
        let off = await manager.isConnected(name: "mock-off")
        XCTAssertFalse(off)
        // 未注册名 → false
        let nope = await manager.isConnected(name: "nope")
        XCTAssertFalse(nope)
        let nopePing = await manager.ping(name: "nope")
        XCTAssertFalse(nopePing)
    }

    /// refreshTools（无注册表）listTools 失败 → descriptor 标记不可用（L373 分支）
    func testRefreshToolsFailureMarksUnavailable() async {
        let manager = MCPServerManager()
        await manager.register(FailingMCPClient(),
                               descriptor: MCPServer(name: "failing-mcp", transport: "in-memory"))
        await manager.refreshTools(for: "failing-mcp")
        let servers = await manager.servers()
        let failing = servers.first { $0.name == "failing-mcp" }
        guard let failing else {
            return XCTFail("failing-mcp 应已注册")
        }
        XCTAssertEqual(failing.isAvailable, false)
        XCTAssertNil(failing.toolCount)
    }

    /// refreshTools(into:) listTools 失败 → 移除旧工具后返回 0（L398-399 分支）
    func testRefreshToolsIntoRegistryFailureReturnsZero() async {
        let manager = MCPServerManager()
        let registry = ToolRegistry()
        await manager.register(FailingMCPClient(),
                               descriptor: MCPServer(name: "failing-mcp", transport: "in-memory"))
        let count = await manager.refreshTools(for: "failing-mcp", into: registry)
        XCTAssertEqual(count, 0)
        let servers = await manager.servers()
        XCTAssertEqual(servers.first { $0.name == "failing-mcp" }?.isAvailable, false)
        let names = await registry.names()
        XCTAssertTrue(names.isEmpty)
    }

    // MARK: - MCPDiscovery 兜底分支

    /// 配置缺失/损坏 → 空数组（不抛错）
    func testLoadConfigsMissingOrCorruptedReturnsEmpty() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-mcp-missing-\(UUID().uuidString)/servers.json")
        XCTAssertTrue(MCPDiscovery.loadConfigs(url: missing).isEmpty)

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-mcp-corrupt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        let corrupt = dir.appendingPathComponent("servers.json")
        try "这不是 JSON".write(to: corrupt, atomically: true, encoding: .utf8)
        XCTAssertTrue(MCPDiscovery.loadConfigs(url: corrupt).isEmpty)
        try FileManager.default.removeItem(at: dir)
    }
}
