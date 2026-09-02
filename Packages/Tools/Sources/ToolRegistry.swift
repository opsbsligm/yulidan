import Foundation
import LLM
import Session

/// 工具注册表 — 管理所有可用工具
public actor ToolRegistry {
    private var tools: [String: any Tool] = [:]

    public init() {}

    /// 注册工具
    public func register(_ tool: any Tool) {
        tools[tool.name] = tool
    }

    /// 获取工具
    public func tool(named name: String) -> (any Tool)? {
        tools[name]
    }

    /// 稳定分类序（与 ToolListView 分类栏一致：文件/终端/MCP/网络/代理，技能次之，未归类最后）
    private static let categoryOrder: [String: Int] = [
        "filesystem": 0,
        "terminal": 1,
        "mcp": 2,
        "network": 3,
        "agent": 4,
        "skills": 5,
        "general": 6,
    ]

    /// 获取所有工具 Schema（稳定序：分类序 → 名称。
    /// 字典迭代序不确定，裸 values 会让展示列表与 LLM wire 每次重建时顺序漂移
    /// ——2026-08-22 并发门禁 3 处测试 flaky 的共同根因）
    public func schemas() -> [ToolSchema] {
        tools.values.map(\.schema).sorted { a, b in
            let ca = Self.categoryOrder[BuiltinTools.category(for: a.name).id] ?? 99
            let cb = Self.categoryOrder[BuiltinTools.category(for: b.name).id] ?? 99
            if ca != cb {
                return ca < cb
            }
            return a.name < b.name
        }
    }

    /// 清除所有工具
    public func clear() {
        tools.removeAll()
    }

    /// 原子全量替换：一次性换入完整工具集。
    /// 语义 = 循环 register（同名后者覆盖），但不存在 clear→register 之间的读取空窗，
    /// 并发读方（Agent 对话中的 tool(named:)）任一时刻只会看到旧集合或新集合。
    public func replaceAll(_ newTools: [any Tool]) {
        var next: [String: any Tool] = [:]
        for tool in newTools {
            next[tool.name] = tool
        }
        tools = next
    }

    /// 全部工具名（MCP list_changed 重装配时清理旧工具用）
    public func names() -> [String] {
        tools.keys.sorted()
    }

    /// 按名注销（不存在时静默）
    public func unregister(named name: String) {
        tools[name] = nil
    }
}
