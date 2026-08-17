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
        let greet = tools.first { $0.name == "mcp_mock_greet" }
        let res = try try await XCTUnwrap(greet?.execute(["name": "Agent"], context: context()))
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
}
