import Foundation
import MCP
import Testing
import Tools
import XCTest

// MARK: - v2 假服务器（listChanged 能力 + 服务器→客户端请求 + 动态工具清单）

private let fakeMCPServerV2Source = #"""
import json, sys


def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


state = {"changed": False}


def tools():
    result = [
        {"name": "echo", "description": "echo text",
         "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}},
        {"name": "add", "description": "a+b",
         "inputSchema": {"type": "object", "properties": {"a": {"type": "number"}, "b": {"type": "number"}}, "required": ["a", "b"]}},
        {"name": "notify", "description": "emit list_changed notification", "inputSchema": {"type": "object"}},
        {"name": "server_request", "description": "send server->client request", "inputSchema": {"type": "object"}},
    ]
    if state["changed"]:
        result.append({"name": "after_change", "description": "appears after change", "inputSchema": {"type": "object"}})
    return result


def main():
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
        params = msg.get("params") or {}
        if method == "initialize":
            send({"jsonrpc": "2.0", "id": mid, "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {"listChanged": True}},
                "serverInfo": {"name": "fake-mcp-v2", "version": "2.0.0"}}})
        elif method == "notifications/initialized":
            pass
        elif method == "ping":
            send({"jsonrpc": "2.0", "id": mid, "result": {}})
        elif method == "tools/list":
            send({"jsonrpc": "2.0", "id": mid, "result": {"tools": tools()}})
        elif method == "tools/call":
            name = params.get("name")
            args = params.get("arguments") or {}
            if name == "echo":
                send({"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": "echo: " + str(args.get("text", ""))}]}})
            elif name == "add":
                total = float(args.get("a", 0)) + float(args.get("b", 0))
                send({"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": str(total)}]}})
            elif name == "notify":
                send({"jsonrpc": "2.0", "method": "notifications/tools/list_changed", "params": {}})
                state["changed"] = True
                send({"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": "notified"}]}})
            elif name == "server_request":
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
                if reply is None:
                    text = "got-no-reply"
                elif "result" in reply:
                    text = "got-result:" + json.dumps(reply["result"])
                else:
                    text = "got-error:" + json.dumps(reply.get("error"))
                send({"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": text}]}})
            else:
                send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "unknown tool: " + str(name)}})


main()
"""#

final class MCPProtocolExtensionTests: XCTestCase {
    private func writeV2ServerScript() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-mcp-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("fake_server_v2.py").path
        try fakeMCPServerV2Source.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func makeClient(scriptPath: String) -> StdioMCPClient {
        StdioMCPClient(name: "fake", configuration: StdioMCPConfiguration(
            command: "/usr/bin/env",
            arguments: ["python3", scriptPath],
            startupTimeout: 10
        ))
    }

    // MARK: 能力协商

    func testCapabilitiesNegotiated() async throws {
        let script = try writeV2ServerScript()
        defer { try? FileManager.default.removeItem(atPath: script) }
        let client = makeClient(scriptPath: script)
        defer { Task { await client.stop() } }
        _ = try await client.listTools() // 触发 start + 握手
        let caps = await client.capabilities()
        XCTAssertNotNil(caps)
        XCTAssertEqual(caps?.protocolVersion, "2024-11-05")
        XCTAssertEqual(caps?.serverName, "fake-mcp-v2")
        XCTAssertEqual(caps?.serverVersion, "2.0.0")
        XCTAssertEqual(caps?.toolsListChanged, true)
    }

    func testPing() async throws {
        let script = try writeV2ServerScript()
        defer { try? FileManager.default.removeItem(atPath: script) }
        let client = makeClient(scriptPath: script)
        defer { Task { await client.stop() } }
        try await client.ping()
    }

    // MARK: 双向通信

    func testListChangedInvalidatesCache() async throws {
        let script = try writeV2ServerScript()
        defer { try? FileManager.default.removeItem(atPath: script) }
        let client = makeClient(scriptPath: script)
        defer { Task { await client.stop() } }
        let box = NotificationBox()
        client.onNotification = { note in
            Task { await box.append(note.method) }
        }
        let first = try await client.listTools()
        XCTAssertEqual(first.map(\.name).sorted(), ["add", "echo", "notify", "server_request"])
        _ = try await client.callTool(name: "notify", arguments: [:])
        let notified = await eventually { await box.all.contains("notifications/tools/list_changed") }
        XCTAssertTrue(notified, "3 秒内应收到 list_changed 通知")
        let second = try await client.listTools()
        XCTAssertTrue(second.map(\.name).contains("after_change"), "list_changed 后应重新拉取工具清单")
        let methods = await box.all
        XCTAssertTrue(methods.contains("notifications/tools/list_changed"))
    }

    func testServerRequestAutoMethodNotFound() async throws {
        let script = try writeV2ServerScript()
        defer { try? FileManager.default.removeItem(atPath: script) }
        let client = makeClient(scriptPath: script)
        defer { Task { await client.stop() } }
        // 未设 onServerRequest：客户端应自动回 -32601
        let out = try await client.callTool(name: "server_request", arguments: [:])
        XCTAssertTrue(out.contains("got-error"))
        XCTAssertTrue(out.contains("-32601"), "自动应答应为 MethodNotFound（实际：\(out)）")
        XCTAssertTrue(out.contains("client/echo"))
    }

    func testServerRequestHandlerReplies() async throws {
        let script = try writeV2ServerScript()
        defer { try? FileManager.default.removeItem(atPath: script) }
        let client = makeClient(scriptPath: script)
        defer { Task { await client.stop() } }
        let seen = MethodBox()
        client.onServerRequest = { method, _ in
            Task { await seen.record(method) }
            return #"""
            {"echoed": 42}
            """#
        }
        let out = try await client.callTool(name: "server_request", arguments: [:])
        XCTAssertTrue(out.contains("got-result"), "应收到处理器应答（实际：\(out)）")
        XCTAssertTrue(out.contains("echoed"))
        let recorded = await eventually { await seen.all == ["client/echo"] }
        XCTAssertTrue(recorded, "3 秒内应收到 server→client 请求回调")
        let methods = await seen.all
        XCTAssertEqual(methods, ["client/echo"])
    }

    // MARK: 适配器必填参数

    func testAdapterRequiredParametersFromSchema() {
        let spec = MCPToolSpec(name: "t", description: "d",
                               inputSchema: #"{"type":"object","properties":{"a":{}},"required":["a","b"]}"#)
        let adapter = MCPToolAdapter(client: MockMCPClient(name: "x"), spec: spec)
        XCTAssertEqual(adapter.requiredParameters, ["a", "b"])
        let plain = MCPToolAdapter(client: MockMCPClient(name: "x"), spec: MCPToolSpec(name: "p", description: "d"))
        XCTAssertEqual(plain.requiredParameters, [])
    }

    // MARK: 服务发现

    func testDiscoveryLoadSaveRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-configs-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let configs = [
            MCPServerConfig(name: "alpha", command: "/usr/bin/env", arguments: ["python3", "a.py"]),
            MCPServerConfig(name: "beta", command: "/opt/mcp/beta", arguments: ["--port", "9000"],
                            environment: ["K": "V"], workingDirectory: "/tmp"),
        ]
        try MCPDiscovery.save(configs, url: url)
        let loaded = MCPDiscovery.loadConfigs(url: url)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].name, "alpha")
        XCTAssertEqual(loaded[1].environment, ["K": "V"])
        XCTAssertEqual(loaded[1].workingDirectory, "/tmp")
    }

    func testDiscoveryLoadMissingFileReturnsEmpty() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-missing-\(UUID().uuidString).json")
        XCTAssertTrue(MCPDiscovery.loadConfigs(url: url).isEmpty)
    }

    func testDiscoveryProbeGoodAndBad() async throws {
        let script = try writeV2ServerScript()
        defer { try? FileManager.default.removeItem(atPath: script) }
        let configs = [
            MCPServerConfig(name: "good", command: "/usr/bin/env", arguments: ["python3", script]),
            MCPServerConfig(name: "bad", command: "/nonexistent-mcp-\(UUID().uuidString)", arguments: []),
        ]
        let results = await MCPDiscovery.discover(configs: configs)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].isAvailable, true)
        XCTAssertEqual(results[0].toolCount, 4)
        XCTAssertTrue((results[0].serverInfo ?? "").hasPrefix("fake-mcp-v2"))
        XCTAssertEqual(results[1].isAvailable, false)
    }

    // MARK: 管理器生命周期 + 自动注册

    func testManagerConnectInstallAndRefreshOnListChanged() async throws {
        let script = try writeV2ServerScript()
        defer { try? FileManager.default.removeItem(atPath: script) }
        let config = MCPServerConfig(name: "fake", command: "/usr/bin/env", arguments: ["python3", script])
        let manager = MCPServerManager()
        let registry = ToolRegistry()
        let descriptor = await manager.connectStdio(config, into: registry)
        XCTAssertTrue(descriptor.isAvailable)
        XCTAssertEqual(descriptor.toolCount, 4)
        XCTAssertTrue((descriptor.serverInfo ?? "").hasPrefix("fake-mcp-v2"))
        var names = await registry.names()
        XCTAssertTrue(names.contains("mcp_fake_echo"), "MCP 工具应自动注册进本地注册表")
        let pingOK = await manager.ping(name: "fake")
        XCTAssertTrue(pingOK)

        // 触发 list_changed → 管理器自动重装配注册表
        _ = try await manager.callTool(client: "fake", name: "notify", arguments: [:])
        try await Task.sleep(for: .milliseconds(300))
        names = await registry.names()
        XCTAssertTrue(names.contains("mcp_fake_after_change"), "list_changed 后新工具应自动进入注册表")
        let servers = await manager.servers()
        XCTAssertEqual(servers.first?.toolCount, 5)

        // ping 断开前后
        await manager.disconnect(name: "fake")
        let pingAfter = await manager.ping(name: "fake")
        XCTAssertEqual(pingAfter, false)
        let serversAfter = await manager.servers()
        XCTAssertTrue(serversAfter.isEmpty)
    }

    func testManagerConnectFailingServerMarkedUnavailable() async {
        let manager = MCPServerManager()
        let config = MCPServerConfig(name: "dead", command: "/nonexistent-mcp-\(UUID().uuidString)", arguments: [])
        let descriptor = await manager.connectStdio(config)
        XCTAssertEqual(descriptor.isAvailable, false)
        let servers = await manager.servers()
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers.first?.isAvailable, false)
        // makeTools 跳过不可用服务器，不抛
        let tools = await manager.makeTools()
        XCTAssertTrue(tools.isEmpty)
    }
}

// MARK: - 收集器

/// 轮询直到条件满足或超时（替代固定 sleep，防事件循环调度抖动导致瞬态失败）
private func eventually(_ timeout: TimeInterval = 3, _ condition: @escaping () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return await condition()
}

actor NotificationBox {
    private(set) var all: [String] = []
    func append(_ s: String) {
        all.append(s)
    }
}

actor MethodBox {
    private(set) var all: [String] = []
    func record(_ s: String) {
        all.append(s)
    }
}
