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

    /// 获取所有工具 Schema
    public func schemas() -> [ToolSchema] {
        tools.values.map(\.schema)
    }

    /// 清除所有工具
    public func clear() {
        tools.removeAll()
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
