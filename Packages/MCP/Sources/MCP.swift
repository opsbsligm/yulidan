import Foundation
import ServiceContainer
import Tools

// MARK: - 类型

/// MCP 工具规格（对应协议 tools/list 的条目）
public struct MCPToolSpec: Sendable, Hashable {
    public let name: String
    public let description: String
    public let inputSchema: String

    public init(name: String, description: String, inputSchema: String = "{}") {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// MCP 服务器连接描述（UI 列表展示用）
public struct MCPServer: Sendable, Identifiable {
    public let id: String
    public let name: String
    /// 传输方式：stdio / http
    public let transport: String
    public var isAvailable: Bool

    public init(id: String = UUID().uuidString, name: String, transport: String = "stdio", isAvailable: Bool = true) {
        self.id = id
        self.name = name
        self.transport = transport
        self.isAvailable = isAvailable
    }
}

/// MCP 错误
public enum MCPError: Error, Sendable, CustomStringConvertible {
    case unknownTool(String)
    case unknownClient(String)
    case serverFailed(String)

    public var description: String {
        switch self {
        case let .unknownTool(name):
            "MCP 工具不存在：\(name)"
        case let .unknownClient(name):
            "MCP 客户端未注册：\(name)"
        case let .serverFailed(reason):
            "MCP 服务器调用失败：\(reason)"
        }
    }
}

// MARK: - 客户端

/// MCP 客户端抽象。真实 stdio/HTTP 客户端后续实现同一协议即可接入。
public protocol MCPClient: Sendable {
    var name: String { get }
    func listTools() async throws -> [MCPToolSpec]
    func callTool(name: String, arguments: [String: String]) async throws -> String
}

/// 内存版 mock 客户端：无真实服务器时用于 UI 与集成流程开发
public actor MockMCPClient: MCPClient {
    public let name: String
    private struct Entry {
        let spec: MCPToolSpec
        let handler: @Sendable ([String: String]) async throws -> String
    }

    private var entries: [String: Entry] = [:]

    public init(name: String = "mock-mcp") {
        self.name = name
    }

    /// 注册一个工具及处理器
    public func addTool(_ spec: MCPToolSpec, handler: @escaping @Sendable ([String: String]) async throws -> String) {
        entries[spec.name] = Entry(spec: spec, handler: handler)
    }

    public func listTools() async throws -> [MCPToolSpec] {
        entries.values.map(\.spec).sorted { $0.name < $1.name }
    }

    public func callTool(name: String, arguments: [String: String]) async throws -> String {
        guard let entry = entries[name] else {
            throw MCPError.unknownTool(name)
        }
        return try await entry.handler(arguments)
    }
}

// MARK: - Tool 适配器

/// 把单个 MCP 工具映射为本地 Tool（Agent 循环可直接调用）
public struct MCPToolAdapter: Tool {
    public let client: any MCPClient
    public let spec: MCPToolSpec

    public init(client: any MCPClient, spec: MCPToolSpec) {
        self.client = client
        self.spec = spec
    }

    /// 本地工具名加前缀，避免与内置工具重名
    public var name: String {
        "mcp_\(client.name)_\(spec.name)"
    }

    public var description: String {
        "[MCP:\(client.name)] \(spec.description)"
    }

    public var parameterSchema: String {
        spec.inputSchema
    }

    public func execute(_ args: [String: String], context: ToolRunContext) async throws -> ToolResult {
        if context.signal.isCancelled {
            return ToolResult(content: [.text("已取消")],
                              error: ToolError(name: name, code: "cancelled", message: "调用已取消"))
        }
        do {
            let output = try await client.callTool(name: spec.name, arguments: args)
            return ToolResult(content: [.text(output)], meta: ["mcp_tool": name, "server": client.name])
        } catch {
            return ToolResult(content: [.text("❌ MCP 工具调用失败：\(error.localizedDescription)")],
                              error: ToolError(name: name, code: "mcp_call_failed", message: error.localizedDescription))
        }
    }
}

// MARK: - 管理器

/// MCP 客户端注册表：管理已注册客户端，批量生成本地 Tool
public actor MCPServerManager {
    private var clients: [String: any MCPClient] = [:]
    private var descriptors: [String: MCPServer] = [:]

    public init() {}

    /// 注册客户端（descriptor 缺省时按 client.name 生成）
    public func register(_ client: any MCPClient, descriptor: MCPServer? = nil) {
        clients[client.name] = client
        descriptors[client.name] = descriptor ?? MCPServer(name: client.name, transport: "in-memory")
    }

    public func unregister(name: String) {
        clients[name] = nil
        descriptors[name] = nil
    }

    /// 当前服务器列表（UI 展示）
    public func servers() -> [MCPServer] {
        descriptors.values.sorted { $0.name < $1.name }
    }

    /// 把全部客户端的全部工具生成为本地 Tool
    public func makeTools() async -> [any Tool] {
        var tools: [any Tool] = []
        for client in clients.values.sorted(by: { $0.name < $1.name }) {
            guard let specs = try? await client.listTools() else {
                continue
            }
            for spec in specs {
                tools.append(MCPToolAdapter(client: client, spec: spec))
            }
        }
        return tools
    }
}
