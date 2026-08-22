import Foundation
@testable import LLM
@testable import ServiceContainer
@testable import Session
import Testing
@testable import Tools

private final class MockTool: Tool, @unchecked Sendable {
    var name: String = "mock"
    var description: String = "A mock tool"
    var parameterSchema: String = "{}"
    var executeResult: ToolResult?
    var executeError: Error?
    var executeCallCount: Int = 0

    func execute(_: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        executeCallCount += 1
        if let error = executeError {
            throw error
        }
        return executeResult ?? ToolResult(content: [.text("mock result")])
    }
}

@Suite("ToolRegistry Tests")
struct ToolRegistryTests {
    @Test("Register and retrieve")
    func testRegister() async {
        let registry = ToolRegistry()
        let tool = MockTool()
        await registry.register(tool)
        #expect(await registry.tool(named: "mock") != nil)
    }

    @Test("Not found")
    func notFound() async {
        let registry = ToolRegistry()
        #expect(await registry.tool(named: "nope") == nil)
    }

    @Test("Get schemas")
    func testSchemas() async {
        let registry = ToolRegistry()
        await registry.register(MockTool())
        let schemas = await registry.schemas()
        #expect(schemas.count == 1)
        #expect(schemas[0].name == "mock")
    }

    @Test("schemas 稳定序：分类序→名称，重建/扩容不漂移（字典序漂移根因回归）")
    func stableSchemaOrder() async {
        let registry = ToolRegistry()
        // 故意以乱序注册（与分类/字母序均不同）
        let names = ["mcp_x", "read_file", "web_fetch", "use_skill", "exec_command", "write_file", "zzz_unknown", "list_skills"]
        for n in names {
            let t = MockTool()
            t.name = n
            await registry.register(t)
        }
        let first = await registry.schemas().map(\.name)
        // 期望：filesystem（read_file, write_file）→ terminal（exec_command）→ mcp（mcp_x）
        //      → network（web_fetch）→ skills（list_skills, use_skill）→ general（zzz_unknown）
        #expect(first == ["read_file", "write_file", "exec_command", "mcp_x", "web_fetch", "list_skills", "use_skill", "zzz_unknown"])
        // 清空后反序重注册（模拟 refreshTools 全量重建）：顺序必须完全一致
        await registry.clear()
        for n in names.reversed() {
            let t = MockTool()
            t.name = n
            await registry.register(t)
        }
        let second = await registry.schemas().map(\.name)
        #expect(first == second)
        // 再扩注册一个工具（模拟刷新窗口内 MCP 连接完成）：新工具落位正确，既有工具顺序不被扰动
        let extra = MockTool()
        extra.name = "mcp_a"
        await registry.register(extra)
        let third = await registry.schemas().map(\.name)
        #expect(third == ["read_file", "write_file", "exec_command", "mcp_a", "mcp_x", "web_fetch", "list_skills", "use_skill", "zzz_unknown"])
    }

    @Test("Clear")
    func testClear() async {
        let registry = ToolRegistry()
        await registry.register(MockTool())
        await registry.clear()
        #expect(await registry.tool(named: "mock") == nil)
    }
}

@Suite("ToolPipeline Tests")
struct ToolPipelineTests {
    @Test("Execute tool")
    func testExecute() async throws {
        let registry = ToolRegistry()
        let pipeline = ToolPipeline(registry: registry)
        let tool = MockTool()
        tool.executeResult = ToolResult(content: [.text("ok")])
        await registry.register(tool)
        let call = ToolCall(name: "mock", arguments: ["k": "v"])
        let result = try await pipeline.execute(call)
        #expect(result.content.count == 1)
    }

    @Test("Tool not found throws")
    func testNotFound() async {
        let registry = ToolRegistry()
        let pipeline = ToolPipeline(registry: registry)
        do {
            _ = try await pipeline.execute(ToolCall(name: "nope", arguments: [:]))
            Issue.record("Expected error")
        } catch {}
    }

    @Test("Pre-execute reject")
    func reject() async {
        let registry = ToolRegistry()
        let pipeline = ToolPipeline(registry: registry)
        await pipeline.addPreExecuteHandler { _ in false }
        do {
            _ = try await pipeline.execute(ToolCall(name: "mock", arguments: [:]))
            Issue.record("Expected error")
        } catch {}
    }

    @Test("Pre-execute allow")
    func allow() async throws {
        let registry = ToolRegistry()
        let pipeline = ToolPipeline(registry: registry)
        await pipeline.addPreExecuteHandler { _ in true }
        let tool = MockTool()
        tool.executeResult = ToolResult(content: [.text("allowed")])
        await registry.register(tool)
        let result = try await pipeline.execute(ToolCall(name: "mock", arguments: [:]))
        #expect(result.content.count == 1)
    }

    @Test("Post-execute handler receives result")
    func postHandler() async throws {
        let registry = ToolRegistry()
        let pipeline = ToolPipeline(registry: registry)
        await pipeline.addPreExecuteHandler { _ in true }
        final class Box: @unchecked Sendable {
            var seen: [String] = []
        }
        let box = Box()
        await pipeline.addPostExecuteHandler { result in
            box.seen.append(result.content.first.flatMap { block -> String? in
                if case let .text(t) = block {
                    return t
                }
                return nil
            } ?? "")
        }
        let tool = MockTool()
        tool.executeResult = ToolResult(content: [.text("done")])
        await registry.register(tool)
        _ = try await pipeline.execute(ToolCall(name: "mock", arguments: [:]))
        #expect(box.seen == ["done"])
    }
}

@Suite("ToolCall Tests")
struct ToolCallTests {
    @Test("Init")
    func testInit() {
        let call = ToolCall(name: "test", arguments: ["k": "v"])
        #expect(call.name == "test")
        #expect(call.arguments["k"] == "v")
    }
}

@Suite("CancellationToken Tests")
struct CancellationTokenTests {
    @Test("Not cancelled initially")
    func notCancelled() {
        let t = CancellationToken()
        #expect(t.isCancelled == false)
    }

    @Test("Cancel sets flag")
    func testCancel() {
        let t = CancellationToken()
        t.cancel()
        #expect(t.isCancelled)
    }
}
