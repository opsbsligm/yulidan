import Foundation

// MARK: - 服务协议（DI 边界）

/// 提示词服务协议（ServiceContainer 注册用；插件/上层只依赖此协议）
public protocol PromptService: Sendable {
    /// 渲染系统提示词
    func renderSystemPrompt(template: String, model: String, context: PromptContext) async throws -> String
    /// 渲染并返回完整产物（含指纹/段落/估算 token）
    func renderDetailed(template: String, model: String, context: PromptContext) async throws -> RenderedPrompt
}

// MARK: - 引擎门面

/// 提示词引擎门面：模板存储 + 渲染器 + 内置模板
///
/// 用法（组装层）：
/// ```swift
/// let engine = PromptEngine.makeDefault()
/// let prompt = try await engine.renderSystemPrompt(template: "agent", model: cfg.model, context: ctx)
/// ```
public final class PromptEngine: PromptService, Sendable {
    /// 默认主 Agent 模板名
    public static let agentTemplate = "agent"
    /// 默认子 Agent 模板名
    public static let subagentTemplate = "subagent"

    public let store: PromptTemplateStore
    public let renderer: PromptRenderer

    public init(store: PromptTemplateStore, renderer: PromptRenderer) {
        self.store = store
        self.renderer = renderer
    }

    /// 创建带内置模板的默认引擎
    public static func makeDefault() -> PromptEngine {
        let store = PromptTemplateStore()
        let engine = PromptEngine(store: store, renderer: PromptRenderer(store: store))
        Task { await BuiltInPromptTemplates.install(into: store) }
        return engine
    }

    public func renderSystemPrompt(template: String, model: String, context: PromptContext = .empty) async throws -> String {
        try await renderDetailed(template: template, model: model, context: context).text
    }

    public func renderDetailed(template: String, model: String, context: PromptContext = .empty) async throws -> RenderedPrompt {
        try await renderer.render(template: template, model: model, context: context)
    }
}

// MARK: - 进程级共享引擎

/// 进程级共享提示词引擎（actor 保证初始化线程安全；各入口复用同一实例）
public actor SharedPromptEngine {
    public static let instance = SharedPromptEngine()
    private var engine: PromptEngine?

    public func get() async -> PromptEngine {
        if let existing = engine {
            return existing
        }
        let store = PromptTemplateStore()
        let created = PromptEngine(store: store, renderer: PromptRenderer(store: store))
        await BuiltInPromptTemplates.install(into: store)
        engine = created
        return created
    }
}
