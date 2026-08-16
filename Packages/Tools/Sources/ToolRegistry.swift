import Session
import LLM
import Foundation

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
        return tools[name]
    }
    
    /// 获取所有工具 Schema
    public func schemas() -> [ToolSchema] {
        return tools.values.map { $0.schema }
    }
    
    /// 清除所有工具
    public func clear() {
        tools.removeAll()
    }
}
