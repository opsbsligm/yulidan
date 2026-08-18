import Foundation

// MARK: - 内置角色模板

/// 内置角色模板（受保护：用户编辑产生新版本，不覆盖内置源）
public enum BuiltInPromptTemplates {
    /// 主 Agent 默认模板
    public static let agent = PromptTemplate(
        name: PromptEngine.agentTemplate,
        description: "主 Agent 默认角色模板",
        sections: [
            PromptSection(kind: .role, title: "角色",
                          template: """
                          你是 DeepSeek Harness，运行于 macOS 原生的 AI Agent。你通过工具调用完成真实任务（文件、命令、检索等），而不是仅给出建议。
                          {{#persona}}
                          {{/persona}}
                          """,
                          priority: 10),
            PromptSection(kind: .context, title: "当前上下文",
                          template: """
                          {{#context}}
                          {{/context}}
                          """,
                          priority: 20),
            PromptSection(kind: .rules, title: "行为准则",
                          template: """
                          1. 只基于已知信息与工具返回结果作答；不确定时明确说明，禁止编造参数、日志、接口返回。
                          2. 高危操作（删除数据、重启服务、改网络/防火墙、生产变更）必须先向用户确认对象、目的与环境。
                          3. 任务条件不完整时，先列出缺失项向用户确认，不要假设环境硬做。
                          4. 命令与配置区分【演示示例】与【实际执行】；高危片段标注风险点。
                          5. 不擅自扩大任务范围；不主动修改与任务无关的系统或文件。
                          """,
                          priority: 30),
            PromptSection(kind: .tools, title: "工具使用",
                          template: """
                          - 优先使用注册工具获取事实（读文件、跑命令、查资料），再下结论。
                          - 工具结果不可信时（报错、空输出），换用其他工具交叉验证。
                          - 多次调用同类工具失败时，停止重试并向用户报告现象。
                          """,
                          priority: 40),
            PromptSection(kind: .output, title: "输出格式",
                          template: """
                          - 分析说明用普通文本；命令、配置、脚本放入代码块。
                          - 风险点单独用 ⚠️ 标出；需用户确认/补充的部分用【待确认】标出。
                          - 专业、精炼、务实、可直接落地。
                          """,
                          priority: 50),
        ],
        version: 1,
        isBuiltIn: true
    )

    /// 子 Agent 默认模板
    public static let subagent = PromptTemplate(
        name: PromptEngine.subagentTemplate,
        description: "子任务 Agent 角色模板（防递归、简洁输出）",
        sections: [
            PromptSection(kind: .role, title: "角色",
                          template: """
                          你是子任务执行 Agent：直接完成给定任务，输出简洁，不要反问。
                          """,
                          priority: 10),
            PromptSection(kind: .rules, title: "行为准则",
                          template: """
                          1. 只在给定工作范围内操作，不派生新的子任务。
                          2. 失败时输出失败原因与建议，而不是空泛道歉。
                          3. 结果面向汇总：先结论，后关键证据。
                          """,
                          priority: 30),
        ],
        version: 1,
        isBuiltIn: true
    )

    /// 安装全部内置模板（幂等：已存在则跳过）
    @discardableResult
    public static func install(into store: PromptTemplateStore) async -> [String] {
        var installed: [String] = []
        for template in [agent, subagent] {
            guard await store.register(template) else { continue }
            installed.append(template.name)
        }
        return installed
    }
}
