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
    /// 传输方式：stdio / http / in-memory
    public let transport: String
    public var isAvailable: Bool
    /// 工具数量（探测/连接成功后有值）
    public var toolCount: Int?
    /// 服务器信息（name@version，能力协商后填充）
    public var serverInfo: String?

    public init(id: String = UUID().uuidString, name: String, transport: String = "stdio",
                isAvailable: Bool = true, toolCount: Int? = nil, serverInfo: String? = nil) {
        self.id = id
        self.name = name
        self.transport = transport
        self.isAvailable = isAvailable
        self.toolCount = toolCount
        self.serverInfo = serverInfo
    }
}

/// MCP 服务器启动配置（可持久化；服务发现/连接管理用）
public struct MCPServerConfig: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    /// 可执行文件（如 /usr/bin/env）
    public var command: String
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectory: String?

    public init(id: String = UUID().uuidString,
                name: String,
                command: String,
                arguments: [String],
                environment: [String: String] = [:],
                workingDirectory: String? = nil) {
        self.id = id
        self.name = name
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }
}

/// 能力协商结果（initialize 握手响应解析）
public struct MCPServerCapabilities: Sendable, Equatable {
    public let protocolVersion: String
    public let serverName: String
    public let serverVersion: String
    /// 服务器是否声明 tools.listChanged 通知能力
    public let toolsListChanged: Bool

    public init(protocolVersion: String, serverName: String, serverVersion: String, toolsListChanged: Bool) {
        self.protocolVersion = protocolVersion
        self.serverName = serverName
        self.serverVersion = serverVersion
        self.toolsListChanged = toolsListChanged
    }
}

/// 服务器 → 客户端通知（method + 原始参数 JSON）
public struct MCPNotification: Sendable, Equatable {
    public let method: String
    public let paramsJSON: String?

    public init(method: String, paramsJSON: String? = nil) {
        self.method = method
        self.paramsJSON = paramsJSON
    }
}

/// MCP 错误
public enum MCPError: Error, Sendable, CustomStringConvertible {
    case unknownTool(String)
    case unknownClient(String)
    case serverFailed(String)
    /// JSON-RPC 服务器错误（携带错误码）
    case serverError(code: Int, message: String)
    /// 请求超时
    case requestTimeout(String)
    /// 协议帧异常
    case protocolViolation(String)
    /// 传输断开（进程退出/管道关闭）
    case transportClosed
    /// 无法启动子进程
    case launchFailed(String)

    public var description: String {
        switch self {
        case let .unknownTool(name):
            "MCP 工具不存在：\(name)"
        case let .unknownClient(name):
            "MCP 客户端未注册：\(name)"
        case let .serverFailed(reason):
            "MCP 服务器调用失败：\(reason)"
        case let .serverError(code, message):
            "MCP 服务器错误 [\(code)]：\(message)"
        case let .requestTimeout(reason):
            "MCP \(reason)"
        case let .protocolViolation(reason):
            "MCP 协议异常：\(reason)"
        case .transportClosed:
            "MCP 传输已断开"
        case let .launchFailed(reason):
            "MCP 启动失败：\(reason)"
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

    /// 从 inputSchema 的 required 数组解析必填参数（接入 ToolExecutor 参数预校验）
    public var requiredParameters: [String] {
        guard
            let data = spec.inputSchema.data(using: .utf8),
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let arr = obj["required"] as? [String]
        else {
            return []
        }
        return arr
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

    /// 诊断：stdio 服务器最近的 stderr 输出（内存客户端/未注册名 → 空串）
    public func recentStderr(name: String) async -> String {
        guard let stdio = clients[name] as? StdioMCPClient else { return "" }
        return await stdio.recentStderr
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

    // MARK: - 会话生命周期

    /// 连接 stdio MCP 服务器（启动 + 能力协商 + 工具清单），并挂接 list_changed 自动刷新
    ///
    /// 成功返回带 toolCount/serverInfo 的 descriptor；失败返回 isAvailable=false（不抛，供发现场景批量探测）
    @discardableResult
    public func connectStdio(_ config: MCPServerConfig, into registry: ToolRegistry? = nil) async -> MCPServer {
        let client = StdioMCPClient(name: config.name, configuration: StdioMCPConfiguration(
            command: config.command,
            arguments: config.arguments,
            environment: config.environment,
            workingDirectory: config.workingDirectory
        ))
        clients[config.name] = client
        client.onNotification = { [weak self] note in
            guard note.method == "notifications/tools/list_changed" else { return }
            Task { [weak self, weak client] in
                guard let self, let client else { return }
                await refreshTools(for: client.name)
                if let registry {
                    await refreshTools(for: client.name, into: registry)
                }
            }
        }
        do {
            let specs = try await client.listTools()
            var descriptor = MCPServer(name: config.name, transport: "stdio",
                                       isAvailable: true, toolCount: specs.count)
            if let caps = await client.capabilities() {
                descriptor.serverInfo = "\(caps.serverName)@\(caps.serverVersion)"
            }
            descriptors[config.name] = descriptor
            if let registry {
                await refreshTools(for: config.name, into: registry)
            }
            return descriptor
        } catch {
            let descriptor = MCPServer(name: config.name, transport: "stdio", isAvailable: false)
            descriptors[config.name] = descriptor
            return descriptor
        }
    }

    /// 直接调用某客户端的工具（管理/调试入口）
    public func callTool(client clientName: String, name: String, arguments: [String: String]) async throws -> String {
        guard let client = clients[clientName] else {
            throw MCPError.unknownClient(clientName)
        }
        return try await client.callTool(name: name, arguments: arguments)
    }

    /// 断开并注销（stdio 客户端终止子进程）
    public func disconnect(name: String) async {
        if let client = clients[name] as? StdioMCPClient {
            await client.stop()
        }
        unregister(name: name)
    }

    /// 某服务器当前是否可连通（stdio：进程在跑；内存客户端：注册即可用）
    public func isConnected(name: String) async -> Bool {
        guard let client = clients[name] else { return false }
        if let stdio = client as? StdioMCPClient {
            // 进程死亡/握手失败的客户端不得误报为在线（曾无条件 return true）
            return await (try? stdio.listTools()) != nil
        }
        return descriptors[name]?.isAvailable ?? false
    }

    /// 健康检查 ping（内存客户端直接成功）
    public func ping(name: String) async -> Bool {
        guard let client = clients[name] else { return false }
        if let stdio = client as? StdioMCPClient {
            return await (try? stdio.ping()) != nil
        }
        return true
    }

    /// 更新某客户端的 descriptor（工具数/可用性/服务器信息）
    private func updateDescriptor(_ client: any MCPClient, toolCount: Int?, available: Bool) async {
        guard var d = descriptors[client.name] else { return }
        d.isAvailable = available
        d.toolCount = toolCount
        if let stdio = client as? StdioMCPClient, let caps = await stdio.capabilities() {
            d.serverInfo = "\(caps.serverName)@\(caps.serverVersion)"
        }
        descriptors[client.name] = d
    }

    /// 刷新某客户端的工具清单缓存（list_changed 后调用）
    public func refreshTools(for clientName: String) async {
        guard let client = clients[clientName] else { return }
        do {
            let specs = try await client.listTools()
            await updateDescriptor(client, toolCount: specs.count, available: true)
        } catch {
            await updateDescriptor(client, toolCount: nil, available: false)
        }
    }

    // MARK: - 本地工具注册表自动装配

    /// 把全部 MCP 工具注册进本地 ToolRegistry；返回注册数量
    @discardableResult
    public func installTools(into registry: ToolRegistry) async -> Int {
        let tools = await makeTools()
        for tool in tools {
            await registry.register(tool)
        }
        return tools.count
    }

    /// 重新装配某客户端的工具：先移除旧的 mcp_<name>_*，再按最新清单注册
    @discardableResult
    public func refreshTools(for clientName: String, into registry: ToolRegistry) async -> Int {
        let prefix = "mcp_\(clientName)_"
        for oldName in await registry.names() where oldName.hasPrefix(prefix) {
            await registry.unregister(named: oldName)
        }
        guard let client = clients[clientName] else { return 0 }
        guard let specs = try? await client.listTools() else {
            await updateDescriptor(client, toolCount: nil, available: false)
            return 0
        }
        await updateDescriptor(client, toolCount: specs.count, available: true)
        for spec in specs {
            await registry.register(MCPToolAdapter(client: client, spec: spec))
        }
        return specs.count
    }
}
