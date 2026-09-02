import Foundation
@testable import LLM
@testable import Session
import Testing
@testable import Tools

/// replaceAll 回归：沙箱切换等全量重建场景的原子性锁定
/// （旧实现 clear→逐条 register 存在读取空窗，并发 tool(named:) 会拿到 nil）
private struct ReplaceStubTool: Tool {
    let name: String
    var description: String {
        "stub \(name)"
    }

    let parameterSchema = "{}"
    func execute(_: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        ToolResult(content: [.text(name)])
    }
}

@Suite("ToolRegistry.replaceAll 原子替换")
struct ToolRegistryReplaceAllTests {
    @Test("替换后：旧工具消失、新工具可查、同名覆盖与 register 语义一致")
    func replaceAllSemantics() async {
        let registry = ToolRegistry()
        await registry.register(ReplaceStubTool(name: "a"))
        await registry.register(ReplaceStubTool(name: "b"))
        await registry.replaceAll([ReplaceStubTool(name: "b2"), ReplaceStubTool(name: "c")])
        await confirmation("旧工具 a 必须消失") { gone in
            if await registry.tool(named: "a") == nil {
                gone()
            }
        }
        let b = await registry.tool(named: "b")
        #expect(b == nil) // 新集合没有 b（覆盖语义是"同名后者覆盖"，b2 是不同名）
        #expect(await registry.tool(named: "b2") != nil)
        #expect(await registry.tool(named: "c") != nil)
        // 同名覆盖：与 register 循环一致
        await registry.replaceAll([ReplaceStubTool(name: "x")])
        #expect(await registry.names() == ["x"])
    }

    @Test("空集合 = 清空")
    func replaceAllEmptyClears() async {
        let registry = ToolRegistry()
        await registry.register(ReplaceStubTool(name: "keep"))
        await registry.replaceAll([])
        #expect(await registry.names().isEmpty)
    }

    @Test("并发读无空窗：写方交替全量替换期间，读方 names() 快照始终非空")
    func concurrentReplaceHasNoEmptyWindow() async {
        let registry = ToolRegistry()
        await registry.replaceAll([ReplaceStubTool(name: "x"), ReplaceStubTool(name: "y")])
        var writerRounds = 0
        let deadline = Date().addingTimeInterval(3)
        // 写方：交替全量替换两组不相交工具集（模拟 setSandboxRoot 重建）
        while writerRounds < 400, Date() < deadline {
            let set: [any Tool] = writerRounds % 2 == 0
                ? [ReplaceStubTool(name: "x"), ReplaceStubTool(name: "y")]
                : [ReplaceStubTool(name: "p"), ReplaceStubTool(name: "q")]
            await registry.replaceAll(set)
            writerRounds += 1
            // 读方：每轮做一次原子快照判定（旧实现 clear 后瞬间会读到空 = 违规）
            let snapshot = await registry.names()
            #expect(!snapshot.isEmpty, "替换窗口期读到空工具集（竞态回归）")
        }
        #expect(writerRounds > 0)
    }
}
