import CryptoKit
import Foundation

// MARK: - 渲染结果

/// 渲染产物：最终提示词 + 可追溯指纹
public struct RenderedPrompt: Sendable, Hashable {
    /// 最终系统提示词文本
    public let text: String
    /// 内容指纹（SHA-256：模板版本 + 模型档案 + 渲染文本）
    public let fingerprint: String
    public let templateName: String
    public let templateVersion: Int
    public let model: String
    public let modelFamily: String
    /// 参与渲染的段落标题（按输出顺序）
    public let sectionTitles: [String]
    /// 估算 token 数
    public let estimatedTokens: Int
    public let renderedAt: Date
}

// MARK: - 渲染器（actor）

/// 提示词渲染器：模板 × 模型档案 × 动态上下文 → 最终提示词
///
/// 流程：取模板 → 模型档案匹配 → 段落适配 → 段落渲染 → 指纹。
/// 无状态逻辑全部委托 TemplateRenderer / ModelPromptAdapter（可独立单测）。
public actor PromptRenderer {
    private let store: PromptTemplateStore

    public init(store: PromptTemplateStore) {
        self.store = store
    }

    /// 渲染系统提示词
    ///
    /// - Parameters:
    ///   - template: 模板名（如 "agent"）
    ///   - model: 模型名（用于档案匹配与适配）
    ///   - context: 动态上下文（变量/条件块）
    public func render(
        template: String,
        model: String,
        context: PromptContext = .empty
    ) async throws -> RenderedPrompt {
        guard let base = await store.template(named: template) else {
            throw PromptError.templateNotFound(template)
        }
        let profile = ModelProfileCatalog.profile(for: model)
        let adapted = ModelPromptAdapter.adapt(base.effectiveSections, profile: profile)
        let rendered = adapted.compactMap { section -> String? in
            let text = TemplateRenderer.render(section.template, context: context)
            guard !text.isEmpty else { return nil }
            return section.title.isEmpty ? text : "## \(section.title)\n\(text)"
        }
        let joined = rendered.joined(separator: "\n\n")
        guard !joined.isEmpty else {
            throw PromptError.emptyTemplate(template)
        }
        let titles = adapted.filter { section in
            !TemplateRenderer.render(section.template, context: context).isEmpty
        }.map(\.title)
        let fingerprint = Self.fingerprint(template: base.name, version: base.version,
                                           model: model, family: profile.family, text: joined)
        return RenderedPrompt(
            text: joined,
            fingerprint: fingerprint,
            templateName: base.name,
            templateVersion: base.version,
            model: model,
            modelFamily: profile.family,
            sectionTitles: titles,
            estimatedTokens: ModelPromptAdapter.estimateTokens(joined),
            renderedAt: Date()
        )
    }

    /// 渲染指定历史版本（版本回放/对比）
    public func render(
        template: String,
        version: Int,
        model: String,
        context: PromptContext = .empty
    ) async throws -> RenderedPrompt {
        guard let base = await store.template(named: template, version: version) else {
            throw PromptError.versionNotFound(template: template, version: version)
        }
        let profile = ModelProfileCatalog.profile(for: model)
        let adapted = ModelPromptAdapter.adapt(base.effectiveSections, profile: profile)
        let rendered = try TemplateRenderer.renderTemplate(
            PromptTemplate(name: base.name, description: base.description,
                           sections: adapted, version: base.version,
                           updatedAt: base.updatedAt, isBuiltIn: base.isBuiltIn),
            context: context
        )
        return RenderedPrompt(
            text: rendered,
            fingerprint: Self.fingerprint(template: base.name, version: base.version,
                                          model: model, family: profile.family, text: rendered),
            templateName: base.name,
            templateVersion: base.version,
            model: model,
            modelFamily: profile.family,
            sectionTitles: adapted.map(\.title),
            estimatedTokens: ModelPromptAdapter.estimateTokens(rendered),
            renderedAt: Date()
        )
    }

    private static func fingerprint(template: String, version: Int, model: String, family: String, text: String) -> String {
        let material = "\(template)#\(version)|\(model)|\(family)|\(text)"
        return sha256Hex(material)
    }

    private static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
