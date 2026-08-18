import Agent
import Foundation
import Memory
import Prompt
import RAG
import Tools

/// CLI 工具装配 helpers（从 DSHMain 拆出，控制文件长度）
extension HeadlessCommand {
    /// 记忆提示词上下文：相关长期记忆注入 {{#context}} 条件块
    static func memoryPromptContext(query: String) async -> PromptContext {
        var ctx = PromptContext()
        let memoryEngine = await SharedMemoryEngine.shared.get()
        if let section = await memoryEngine.promptSection(query: query) {
            ctx.blocks["context"] = section
        }
        return ctx
    }

    /// 记忆反馈闭环：本轮 prompt + 最终回复蒸馏 → 长期记忆并落盘
    static func processMemoryFeedback(prompt: String, result: AgentResult) async {
        let assistantText = result.messages.flatMap(\.content).compactMap { block -> String? in
            if case let .text(t) = block {
                return t
            }
            return nil
        }.joined(separator: "\n")
        guard !assistantText.isEmpty else { return }
        let memoryEngine = await SharedMemoryEngine.shared.get()
        await memoryEngine.attachRAG(SharedRAGEngine.shared.get())
        _ = await memoryEngine.consolidateSession(sessionID: "dsh-cli", exchanges: [
            MemoryExchange(role: .user, text: prompt),
            MemoryExchange(role: .assistant, text: assistantText),
        ])
        await memoryEngine.save()
    }

    /// RAG 知识库工具注册（进程级共享索引 ~/.harness/rag/index.json，与 App 同一份库）
    static func registerRAGTools(to tools: ToolRegistry) async {
        let ragEngine = await SharedRAGEngine.shared.get()
        for tool in KnowledgeTools.makeAll(engine: ragEngine) {
            await tools.register(tool)
        }
    }
}
