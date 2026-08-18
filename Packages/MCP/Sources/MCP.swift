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

// MARK: - JSON-RPC 2.0 stdio 真实客户端

/// stdio MCP 服务器启动配置
public struct StdioMCPConfiguration: Sendable {
    /// 可执行文件（如 /usr/bin/env）
    public var command: String
    /// 启动参数
    public var arguments: [String]
    /// 附加环境变量（覆盖继承环境）
    public var environment: [String: String]
    /// 工作目录
    public var workingDirectory: String?
    /// 单次请求超时（秒）
    public var requestTimeout: TimeInterval
    /// 启动握手超时（秒）
    public var startupTimeout: TimeInterval
    /// stderr 诊断缓冲上限（字节）
    public var maxStderrBytes: Int

    public init(command: String,
                arguments: [String],
                environment: [String: String] = [:],
                workingDirectory: String? = nil,
                requestTimeout: TimeInterval = 30,
                startupTimeout: TimeInterval = 10,
                maxStderrBytes: Int = 8192) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.requestTimeout = requestTimeout
        self.startupTimeout = startupTimeout
        self.maxStderrBytes = maxStderrBytes
    }
}

/// 通过 stdio（NDJSON JSON-RPC 2.0）连接真实 MCP 服务器
///
/// 协议流程：initialize → notifications/initialized → tools/list → tools/call。
/// 生命周期：首次请求自动 start()，调用 stop() 终止子进程；进程异常退出时
/// 所有挂起请求以 transportClosed 失败。
public actor StdioMCPClient: MCPClient {
    public let name: String
    private let config: StdioMCPConfiguration

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var pending: [Int: CheckedContinuation<String, Error>] = [:]
    private var deadlineTasks: [Int: Task<Void, Never>] = [:]
    private var nextID = 1
    private var started = false
    private var toolsCache: [MCPToolSpec]?
    private var stderrLog = ""
    private var readerStopped = false

    public init(name: String, configuration: StdioMCPConfiguration) {
        self.name = name
        config = configuration
    }

    deinit {
        // 兜底：进程随客户端一起释放；未决请求以 transportClosed 失败，避免 continuation 悬挂
        for task in deadlineTasks.values {
            task.cancel()
        }
        for (_, cont) in pending {
            cont.resume(throwing: MCPError.transportClosed)
        }
        process?.terminate()
    }

    // MARK: 生命周期

    /// 启动子进程并完成 initialize 握手（幂等）
    public func start() async throws {
        guard !started else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.command)
        process.arguments = config.arguments
        if !config.environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(config.environment) { _, new in new }
        }
        if let wd = config.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: (wd as NSString).expandingTildeInPath)
        }
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw MCPError.launchFailed("启动失败：\(error.localizedDescription)")
        }

        self.process = process
        stdinHandle = stdinPipe.fileHandleForWriting

        // 后台读取 stdout（阻塞读在独立线程，避免卡住 actor）
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        let maxStderr = config.maxStderrBytes
        let client = self
        Task.detached {
            Self.pumpStdout(stdoutHandle) { line in
                await client.handleStdoutLine(line)
            }
            Self.pumpStderr(stderrHandle, limit: maxStderr) { chunk in
                await client.appendStderr(chunk)
            }
        }
        Task.detached {
            process.waitUntilExit()
            await client.handleProcessExit()
        }

        // initialize 握手
        let initResult = try await rawRequest(method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": [String: Any](),
            "clientInfo": ["name": "swift-harness", "version": "0.2.0"],
        ], timeout: config.startupTimeout)
        _ = initResult
        try await sendNotification("notifications/initialized")
        started = true
    }

    /// 终止子进程并清理
    public func stop() {
        failAllPending(MCPError.transportClosed)
        if let process, process.isRunning {
            process.terminate()
        }
        try? stdinHandle?.close()
        stdinHandle = nil
        process = nil
        started = false
        toolsCache = nil
        readerStopped = true
    }

    // MARK: MCPClient

    public func listTools() async throws -> [MCPToolSpec] {
        try await start()
        if let toolsCache {
            return toolsCache
        }
        let result = try await performRequest(method: "tools/list", params: [:])
        let tools = (result["tools"] as? [[String: Any]]) ?? []
        let specs = tools.compactMap { raw -> MCPToolSpec? in
            guard let n = raw["name"] as? String else { return nil }
            let desc = raw["description"] as? String ?? ""
            let schema = (try? JSONSerialization.data(withJSONObject: raw["inputSchema"] ?? [:], options: [.fragmentsAllowed]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return MCPToolSpec(name: n, description: desc, inputSchema: schema)
        }
        toolsCache = specs
        return specs
    }

    public func callTool(name toolName: String, arguments: [String: String]) async throws -> String {
        try await start()
        let result = try await performRequest(method: "tools/call", params: [
            "name": toolName,
            "arguments": arguments,
        ])
        let isError = (result["isError"] as? Bool) ?? false
        let content = (result["content"] as? [[String: Any]]) ?? []
        let text = content.compactMap { item -> String? in
            (item["type"] as? String) == "text" ? (item["text"] as? String) : nil
        }.joined(separator: "\n")
        if isError {
            throw MCPError.serverError(code: -1, message: text.isEmpty ? "工具执行失败" : text)
        }
        return text
    }

    // MARK: JSON-RPC 内部

    private func performRequest(method: String, params: [String: Any]) async throws -> [String: Any] {
        let json = try await rawRequest(method: method, params: params, timeout: config.requestTimeout)
        guard let data = json.data(using: .utf8) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [String: Any] ?? [:]
    }

    /// 发送请求并等待响应，返回 result 的 JSON 文本（解析交由调用方）
    private func rawRequest(method: String, params: [String: Any], timeout: TimeInterval) async throws -> String {
        let id = nextID
        nextID += 1
        let payload: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        guard var line = try? JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed]) else {
            throw MCPError.protocolViolation("请求序列化失败")
        }
        line.append(0x0A)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            // 先注册再发送：写失败时 failAllPending 会立即恢复本请求，不会悬挂
            pending[id] = cont
            sendLine(line)
            guard pending[id] != nil else { return }
            deadlineTasks[id] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.failPending(id: id, error: MCPError.requestTimeout("超过 \(Int(timeout))s 未响应"))
            }
        }
    }

    private func sendNotification(_ method: String) async throws {
        let payload: [String: Any] = ["jsonrpc": "2.0", "method": method]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed]) else {
            throw MCPError.protocolViolation("通知序列化失败")
        }
        var line = data
        line.append(0x0A)
        do {
            try stdinHandle?.write(contentsOf: line)
        } catch {
            throw MCPError.transportClosed
        }
    }

    /// 发送一帧 NDJSON；写失败（进程大概率已退出）时所有挂起请求以 transportClosed 失败
    private func sendLine(_ data: Data) {
        do {
            try stdinHandle?.write(contentsOf: data)
        } catch {
            failAllPending(MCPError.transportClosed)
        }
    }

    private func failPending(id: Int, error: Error) {
        cancelDeadline(id)
        guard let cont = pending.removeValue(forKey: id) else { return }
        cont.resume(throwing: error)
    }

    private func failAllPending(_ error: Error) {
        for task in deadlineTasks.values {
            task.cancel()
        }
        deadlineTasks.removeAll()
        let all = pending
        pending.removeAll()
        for (_, cont) in all {
            cont.resume(throwing: error)
        }
    }

    private func cancelDeadline(_ id: Int) {
        deadlineTasks.removeValue(forKey: id)?.cancel()
    }

    // MARK: 服务器消息处理

    private func handleStdoutLine(_ line: String) {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }
        // 响应（带 id）；通知（server→client）忽略
        guard let id = obj["id"] as? Int else { return }
        if let error = obj["error"] as? [String: Any],
           let code = error["code"] as? Int {
            let message = error["message"] as? String ?? "未知错误"
            failPending(id: id, error: MCPError.serverError(code: code, message: message))
            return
        }
        if let result = obj["result"] {
            let json: String
            if result is NSNull {
                json = "null"
            } else {
                let data = (try? JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed])) ?? Data("null".utf8)
                json = String(data: data, encoding: .utf8) ?? "null"
            }
            resumePending(id: id, json)
            return
        }
        failPending(id: id, error: MCPError.protocolViolation("响应缺少 result 字段"))
    }

    private func resumePending(id: Int, _ json: String) {
        cancelDeadline(id)
        guard let cont = pending.removeValue(forKey: id) else { return }
        cont.resume(returning: json)
    }

    private func appendStderr(_ chunk: String) {
        stderrLog += chunk
        if stderrLog.count > config.maxStderrBytes {
            stderrLog = String(stderrLog.suffix(config.maxStderrBytes))
        }
    }

    private func handleProcessExit() {
        readerStopped = true
        failAllPending(MCPError.transportClosed)
        started = false
        toolsCache = nil
    }

    /// 诊断用：最近 stderr 输出
    public var recentStderr: String {
        stderrLog
    }

    // MARK: 管道泵（独立线程阻塞读取，按行切分）

    private static func pumpStdout(_ handle: FileHandle, onLine: @escaping @Sendable (String) async -> Void) {
        // 注意：此工具链上 FileHandle.read(upToCount:) 存在阻塞 bug（poll 可读却永久阻塞），
        // 故直接用原生 read(2) 读取
        let fd = handle.fileDescriptor
        Thread.detachNewThread {
            var buffer = Data()
            var readBuf = [UInt8](repeating: 0, count: 8192)
            while true {
                let n = read(fd, &readBuf, readBuf.count)
                if n < 0 {
                    if errno == EINTR {
                        continue
                    }
                    break
                }
                if n == 0 {
                    break
                }
                buffer.append(contentsOf: readBuf[0 ..< n])
                while let newlineIdx = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer.subdata(in: buffer.startIndex ..< newlineIdx)
                    buffer.removeSubrange(buffer.startIndex ... newlineIdx)
                    if let line = String(data: lineData, encoding: .utf8) {
                        Task { await onLine(line) }
                    }
                }
            }
        }
    }

    private static func pumpStderr(_ handle: FileHandle, limit: Int, onChunk: @escaping @Sendable (String) async -> Void) {
        let fd = handle.fileDescriptor
        Thread.detachNewThread {
            var total = 0
            var readBuf = [UInt8](repeating: 0, count: 4096)
            while total < limit * 2 {
                let n = read(fd, &readBuf, readBuf.count)
                if n < 0 {
                    if errno == EINTR {
                        continue
                    }
                    break
                }
                if n == 0 {
                    break
                }
                total += n
                if let text = String(data: Data(readBuf[0 ..< n]), encoding: .utf8) {
                    Task { await onChunk(text) }
                }
            }
        }
    }
}
