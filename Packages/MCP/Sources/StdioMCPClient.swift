import Foundation
import ServiceContainer
import Tools

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
    private var negotiatedCapabilities: MCPServerCapabilities?
    /// 服务器 → 客户端通知回调（tools/list_changed 等）
    public nonisolated(unsafe) var onNotification: (@Sendable (MCPNotification) -> Void)?
    /// 服务器 → 客户端请求处理器（method, 参数 JSON 文本 → 结果 JSON 文本）
    /// nil 时自动回 -32601 MethodNotFound（防服务器挂起）
    public nonisolated(unsafe) var onServerRequest: (@Sendable (String, String?) async throws -> String)?

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

        // initialize 握手 + 能力协商
        let initResult = try await rawRequest(method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": [String: Any](),
            "clientInfo": ["name": "swift-harness", "version": "0.2.0"],
        ], timeout: config.startupTimeout)
        negotiatedCapabilities = Self.parseCapabilities(initResult)
        try await sendNotification("notifications/initialized")
        started = true
    }

    /// 能力协商结果（未 start 前为 nil）
    public func capabilities() -> MCPServerCapabilities? {
        negotiatedCapabilities
    }

    /// 健康检查：ping（协议规定服务器必须应答空 result）
    public func ping() async throws {
        try await start()
        _ = try await performRequest(method: "ping", params: [:])
    }

    static func parseCapabilities(_ json: String) -> MCPServerCapabilities? {
        guard
            let data = json.data(using: .utf8),
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return nil
        }
        let info = obj["serverInfo"] as? [String: Any] ?? [:]
        let caps = obj["capabilities"] as? [String: Any] ?? [:]
        let tools = caps["tools"] as? [String: Any] ?? [:]
        return MCPServerCapabilities(
            protocolVersion: obj["protocolVersion"] as? String ?? "unknown",
            serverName: info["name"] as? String ?? "unknown",
            serverVersion: info["version"] as? String ?? "unknown",
            toolsListChanged: tools["listChanged"] as? Bool ?? false
        )
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
        negotiatedCapabilities = nil
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
        // 服务器 → 客户端请求（method + id）：分发处理器或自动回 MethodNotFound
        if let method = obj["method"] as? String, let id = obj["id"] as? Int {
            let paramsJSON = ((obj["params"] as Any?)
                .flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed]) }
                .flatMap { String(data: $0, encoding: .utf8) })
            Task { [weak self] in
                await self?.handleServerRequest(method: method, paramsJSON: paramsJSON, id: id)
            }
            return
        }
        // 服务器 → 客户端通知（method，无 id）
        if let method = obj["method"] as? String {
            let paramsJSON = ((obj["params"] as Any?)
                .flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed]) }
                .flatMap { String(data: $0, encoding: .utf8) })
            handleIncomingNotification(method: method, paramsJSON: paramsJSON)
            return
        }
        // 响应（带 id，无 method）
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

    /// 处理服务器 → 客户端通知；tools/list_changed 时失效工具缓存
    private func handleIncomingNotification(method: String, paramsJSON: String?) {
        if method == "notifications/tools/list_changed" {
            toolsCache = nil
        }
        onNotification?(MCPNotification(method: method, paramsJSON: paramsJSON))
    }

    /// 处理服务器 → 客户端请求：有处理器则回 result，否则自动回 -32601（防服务器挂起）
    private func handleServerRequest(method: String, paramsJSON: String?, id: Int) async {
        var resultJSON: String?
        var message = "Method not found: \(method)"
        var code = -32601
        if let handler = onServerRequest {
            do {
                resultJSON = try await handler(method, paramsJSON)
            } catch {
                code = -32603
                // String(describing:) 走 CustomStringConvertible 见证：保留 MCPError 自定义描述；
                // LocalizedError 类型回 localizedDescription（行为与旧实现一致，且避免恒真 cast 警告）
                message = String(describing: error)
            }
        }
        let payload: [String: Any] = if let resultJSON, let data = resultJSON.data(using: .utf8),
                                        let value = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) {
            ["jsonrpc": "2.0", "id": id, "result": value]
        } else {
            ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed]) else {
            return
        }
        var line = data
        line.append(0x0A)
        sendLine(line)
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
