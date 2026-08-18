import Agent
import Foundation
import Memory
import Prompt
import RAG
import Skill
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

    /// 技能运行时：加载内置 + 用户技能，注册 4 个技能工具；返回注册表供进化引擎写入
    struct SkillRuntime: Sendable {
        let registry: SkillRegistry
    }

    static func makeSkillRuntime(to tools: ToolRegistry) async -> SkillRuntime {
        let registry = SkillRegistry()
        for skill in BuiltInSkills.makeAll() {
            await registry.register(skill)
        }
        for skill in SkillStore.load(from: SkillStore.userSkillsDirectory) {
            await registry.register(skill)
        }
        for tool in SkillTools.makeAll(registry: registry) {
            await tools.register(tool)
        }
        return SkillRuntime(registry: registry)
    }

    /// 技能进化观测：上报本轮任务（用户原文）+ 按序去重的工具序列；
    /// 相似任务累计达阈值时自动生成技能并注册进注册表（可被后续 use_skill 复用）
    static func observeSkillEvolution(task: String, result: AgentResult, registry: SkillRegistry) async {
        let toolNames = result.steps.flatMap(\.content).compactMap { block -> String? in
            if case let .toolCall(call) = block {
                return call.name
            }
            return nil
        }
        var seen = Set<String>()
        let deduped = toolNames.filter { seen.insert($0).inserted }
        let engine = await SharedSkillEvolution.shared.get(registry: registry)
        await engine.observe(sessionID: "dsh-cli", task: task, toolNames: deduped,
                             succeeded: result.error == nil)
        for candidate in await engine.evaluate() {
            FileHandle.standardError.write(Data("[dsh] 技能自动沉淀：\(candidate.name)（\(candidate.evidenceCount) 次相似任务）\n".utf8))
        }
    }
}
