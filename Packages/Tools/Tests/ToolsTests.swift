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
