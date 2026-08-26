import Foundation
@testable import MCP
import Session
import Testing
import Tools
import XCTest

// MARK: - 覆盖审计轮 17：MCP 残余兜底行（parseCapabilities 直测 / 怪癖服务器兜底链 / 工具列表解析兜底）

/// 服务器→客户端请求记录盒（验证 onServerRequest 分发 + paramsJSON 双 flatMap 闭包）
private final class ServerRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(method: String, paramsJSON: String?)] = []

    func record(_ method: String, _ paramsJSON: String?) {
        lock.lock()
        calls.append((method, paramsJSON))
        lock.unlock()
    }

    var first: (method: String, paramsJSON: String?)? {
        lock.lock()
        defer { lock.unlock() }
        return calls.first
    }
}

/// 怪癖服务器：启动即灌 garbage 行 + 服务器请求 + 通知；tools/list 无 tools 键；
/// tools/call 覆盖空 result / 混合 content / 非标量 result / 无 message 错误
private let quirkyServerSource = #"""
import json, sys


def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


# 启动即发 garbage 行（客户端 handleStdoutLine guard return 分支）
sys.stdout.write("garbage-line-not-json\n")
sys.stdout.flush()
# 服务器→客户端请求（带 params → 两个 flatMap 闭包执行）
send({"jsonrpc": "2.0", "id": 999, "method": "harness/ping", "params": {"a": 1}})
# 服务器→客户端通知（带 params）
send({"jsonrpc": "2.0", "method": "notifications/tools/list_changed", "params": {"n": 1}})

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
            "serverInfo": {"name": "quirky-r17", "version": "7.7"}}})
    elif method == "tools/list":
        send({"jsonrpc": "2.0", "id": mid, "result": {}})
    elif method == "tools/call":
        name = params.get("name")
        if name == "bare":
            send({"jsonrpc": "2.0", "id": mid, "result": {}})
        elif name == "mix":
            send({"jsonrpc": "2.0", "id": mid, "result": {"content": [
                {"type": "image", "data": "x"},
                {"type": "text", "text": "hi"}]}})
        elif name == "nonscalar":
            send({"jsonrpc": "2.0", "id": mid, "result": "hello"})
        elif name == "err-nomsg":
            send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32000}})
        else:
            send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "unknown tool"}})
"""#

/// 工具列表服务器：result 带无 name 条目 / 无 description 条目 / 正常条目
private let toolsListServerSource = #"""
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
    params = msg.get("params") or {}
    if method == "initialize":
        send({"jsonrpc": "2.0", "id": mid, "result": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "serverInfo": {"name": "tools-r17", "version": "1.0"}}})
    elif method == "tools/list":
        send({"jsonrpc": "2.0", "id": mid, "result": {"tools": [
            {"description": "anonymous tool"},
            {"name": "no-desc"},
            {"name": "add", "description": "a+b",
             "inputSchema": {"type": "object", "properties": {"a": {"type": "number"}}}}]}})
    elif method == "tools/call":
        name = params.get("name")
        if name == "add":
            send({"jsonrpc": "2.0", "id": mid, "result": {
                "content": [{"type": "text", "text": "added"}]}})
        else:
            send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "unknown tool"}})
"""#

final class MCPR17GapCoverageTests: XCTestCase {
    private func writeScript(_ source: String, name: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-mcp-r17-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(name).path
        try source.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func makeClient(scriptPath: String) -> StdioMCPClient {
        StdioMCPClient(name: "r17-fake", configuration: StdioMCPConfiguration(
            command: "/usr/bin/env",
            arguments: ["python3", scriptPath],
            environment: ["HARNESS_MCP_R17": "1"], // 非空 → start 的 environment merging 闭包执行
            requestTimeout: 10,
            startupTimeout: 10,
            maxStderrBytes: 4096
        ))
    }

    // MARK: parseCapabilities 直测（internal，@testable 直调）

    /// ① 非 JSON → nil（轮 5 遗留 miss 行）
    func testParseCapabilitiesInvalidJSON() {
        XCTAssertNil(StdioMCPClient.parseCapabilities("not json at all"))
    }

    /// ② 空对象 → 全部 `??` 兜底（protocolVersion/serverName/serverVersion/listChanged）
    func testParseCapabilitiesEmptyObject() {
        let caps = StdioMCPClient.parseCapabilities("{}")
        XCTAssertNotNil(caps)
        XCTAssertEqual(caps?.protocolVersion, "unknown")
        XCTAssertEqual(caps?.serverName, "unknown")
        XCTAssertEqual(caps?.serverVersion, "unknown")
        XCTAssertEqual(caps?.toolsListChanged, false)
    }

    /// ③ 富 JSON → 真实值（与 ② 互补）
    func testParseCapabilitiesRich() {
        let json = #"""
        {"protocolVersion":"2025-03-26","serverInfo":{"name":"srv","version":"9.9"},
        "capabilities":{"tools":{"listChanged":true}}}
        """#
        let caps = StdioMCPClient.parseCapabilities(json)
        XCTAssertEqual(caps?.protocolVersion, "2025-03-26")
        XCTAssertEqual(caps?.serverName, "srv")
        XCTAssertEqual(caps?.serverVersion, "9.9")
        XCTAssertEqual(caps?.toolsListChanged, true)
    }

    // MARK: 怪癖服务器（真实子进程 + NDJSON）

    /// ④ garbage 行 guard return + 服务器请求分发（双 flatMap 闭包）+ 完整能力协商
    func testQuirkyServerHandshakeAndServerRequest() async throws {
        let script = try writeScript(quirkyServerSource, name: "quirky_r17.py")
        defer { try? FileManager.default.removeItem(atPath: script) }
        let box = ServerRequestBox()
        let client = makeClient(scriptPath: script)
        defer { Task { await client.stop() } }
        client.onServerRequest = { method, params in
            box.record(method, params)
            return "{}"
        }

        // listTools 触发 start（幂等）：garbage 行被丢弃，握手成功
        let tools = try await client.listTools()
        #expect(tools.isEmpty) // 服务器 result 无 tools 键 → `?? []`
        let caps = await client.capabilities()
        #expect(caps?.serverName == "quirky-r17")
        #expect(caps?.protocolVersion == "2024-11-05")

        // 等待服务器→客户端请求处理器异步落账（pump 已按序分发，至多几轮轮询）
        let deadline = Date().addingTimeInterval(3)
        while box.first == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(box.first?.method == "harness/ping")
        #expect(box.first?.paramsJSON?.contains("a") == true)
    }

    /// ⑤ callTool 空 result → isError/content 双兜底（返回空串不抛错）
    func testCallToolBareResult() async throws {
        let script = try writeScript(quirkyServerSource, name: "quirky_bare.py")
        defer { try? FileManager.default.removeItem(atPath: script) }
        let client = makeClient(scriptPath: script)
        defer { Task { await client.stop() } }
        let text = try await client.callTool(name: "bare", arguments: [:])
        #expect(text.isEmpty)
    }

    /// ⑥ callTool 混合 content → 非文本条目 compactMap nil 分支
    func testCallToolMixedContent() async throws {
        let script = try writeScript(quirkyServerSource, name: "quirky_mix.py")
        defer { try? FileManager.default.removeItem(atPath: script) }
        let client = makeClient(scriptPath: script)
        defer { Task { await client.stop() } }
        let text = try await client.callTool(name: "mix", arguments: [:])
        #expect(text == "hi")
    }

    /// ⑦ callTool 非标量 result（JSON 字符串）→ performRequest `as? [String: Any] ?? [:]`
    func testCallToolNonscalarResult() async throws {
        let script = try writeScript(quirkyServerSource, name: "quirky_nonscalar.py")
        defer { try? FileManager.default.removeItem(atPath: script) }
        let client = makeClient(scriptPath: script)
        defer { Task { await client.stop() } }
        let text = try await client.callTool(name: "nonscalar", arguments: [:])
        #expect(text.isEmpty)
    }

    /// ⑧ callTool 服务器错误无 message → `?? "未知错误"`
    func testCallToolErrorWithoutMessage() async throws {
        let script = try writeScript(quirkyServerSource, name: "quirky_err.py")
        defer { try? FileManager.default.removeItem(atPath: script) }
        let client = makeClient(scriptPath: script)
        defer { Task { await client.stop() } }
        do {
            _ = try await client.callTool(name: "err-nomsg", arguments: [:])
            XCTFail("预期抛出 serverError")
        } catch let error as MCPError {
            guard case let .serverError(code, message) = error else {
                XCTFail("预期 serverError，实际 \(error)")
                return
            }
            #expect(code == -32000)
            #expect(message == "未知错误")
        }
    }

    // MARK: 工具列表解析兜底

    /// ⑨ tools/list 无 name 条目 → compactMap nil 分支；无 description → `?? ""`；
    /// 无 inputSchema → `?? [:]` + flatMap 闭包
    func testToolsListFallbacks() async throws {
        let script = try writeScript(toolsListServerSource, name: "toolslist_r17.py")
        defer { try? FileManager.default.removeItem(atPath: script) }
        let client = makeClient(scriptPath: script)
        defer { Task { await client.stop() } }
        let tools = try await client.listTools()
        #expect(tools.map(\.name) == ["no-desc", "add"])
        #expect(tools.first?.description.isEmpty == true)
        #expect(tools.first?.inputSchema == "{}")
        #expect(try await client.callTool(name: "add", arguments: ["a": "1"]) == "added")
    }
}
