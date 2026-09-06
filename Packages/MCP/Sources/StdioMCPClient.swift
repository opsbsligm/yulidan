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
    /// 入站事件 FIFO（D-25(a2)）：读线程与终止回调只向这里按序投递，单一消费者串行结算。
    /// ⚠️ 必须是 `let` 且类型线程安全：终止通知要在**非隔离**上下文（Foundation 回调线程）直接投递，
    ///    任何「另起 Task 投递」＝旧架构的竞速形状（见 `noteProcessTerminated`）。
    private let inbound = InboundMailbox()
    /// 单一消费者任务（生命周期 = 一次 start() 到 stop()/EOF 取空）
    private var inboundConsumer: Task<Void, Never>?
    /// 收到终止通知，但读端尚未 EOF（清理延迟到 EOF 之后，见 `consumeInbound`）
    private var pendingExit = false
    /// 测试缝（**实例级**，D-24 教训：静态缝会重演跨 suite 互清挂死）：
    /// 在「行已入队、尚未结算」处挂起，供退出事件确定性插入。生产路径恒为 nil ⇒ 零介入。
    var lineGateForTesting: (@Sendable (String) async -> Void)?
    /// 测试专用：设置行处理闸门（传 nil 清除）
    func setLineGateForTesting(_ gate: (@Sendable (String) async -> Void)?) {
        lineGateForTesting = gate
    }

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

        // 进程终止通知＝官方 `Process.terminationHandler`（Apple 原文抽象：
        // 「A completion block the system invokes when the task completes.」；正文：
        // 「The system passes the task object to the block to allow access to the task parameters,
        //  for example to determine if the task completed successfully.」）。
        // ⚠️ 被替换的原实现：`Task.detached { process.waitUntilExit(); await client.handleProcessExit() }`。
        //   两条官方明文说明它为什么危险：
        //   ① `waitUntilExit()`「Blocks the process until the receiver is finished.」——同步阻塞；
        //      写在 Task 体里即跑在 Swift 协作线程池上 ⇒ 每个在册 stdio 客户端长期占死一条协作线程
        //      直到子进程退出。多服务器 + CI 高负载时协作池饥饿，症状正是「互不相干的断言同时超时」
        //      的 flake 家族（D-16 附带项；量化对照见 QUALITY_REPORT 09-06 补记㉕）。
        //   ② 同页下一句：「This method first checks to see if the receiver is still running using
        //      isRunning. Then it polls the current run loop using NSDefaultRunLoopMode until the
        //      task completes.」（官方原文该处 isRunning 为链接）——协作线程池线程没有运行循环，
        //      即该等待方式在我们的执行器上没有官方保证的语义。
        //   回调体因此只做一次 actor hop，不含任何阻塞调用。
        // 取位说明：官方未明文「run() 之后再赋值 handler 是否仍保证回调」，故按我方保守取位放在
        //   run() 之前（这是我们的选择，不是官方要求）。本机实测（macOS 26.5 SDK，探针 /tmp/probe_zombie）：
        //   置 handler 后即使**不持有 Process 强引用**且**不调用 waitUntilExit**，5/5 回调全部触发，
        //   子进程由 Foundation 回收（kill(pid,0) 全部 ESRCH，ps 无残留 ⇒ 无僵尸、无孤儿）。
        let client = self
        // D-25(a2)：终止通知不再另起一条裸 `Task` 去做清理（那正是与响应投递竞速的第二条 hop），
        // 而是把「终止哨兵」投进与 stdout 行**同一条** FIFO，由单一消费者按序结算。
        process.terminationHandler = { [weak self] _ in
            self?.noteProcessTerminated()
        }

        do {
            try process.run()
        } catch {
            throw MCPError.launchFailed("启动失败：\(error.localizedDescription)")
        }

        self.process = process
        stdinHandle = stdinPipe.fileHandleForWriting

        // 后台读取 stdout/stderr（阻塞读在独立线程 Thread.detachNewThread 内，不占协作线程池）。
        // D-25(a2)：stdout 的行与 EOF **同步**入队到入站 FIFO（顺序 == 读线程程序序），
        // 结算由单一消费者 `consumeInbound` 串行执行；stderr 非协议通道，维持原异步投递。
        // ⚠️ stop() 之后重新 start()（重连复用同一实例）时旧 FIFO 处于关闭态，必须 reopen，
        //    否则新进程的事件会被 `append` 直接丢弃。
        inbound.reopen()
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        let maxStderr = config.maxStderrBytes
        let pumpMailbox = inbound
        Self.pumpStdout(stdoutHandle,
                        onLine: { pumpMailbox.append(.line($0)) },
                        onEOF: { pumpMailbox.append(.readerEnded) })
        Self.pumpStderr(stderrHandle, limit: maxStderr) { chunk in
            Task { await client.appendStderr(chunk) }
        }
        inboundConsumer = Task { [weak self] in
            await self?.consumeInbound()
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
        // 关闭入站 FIFO：消费者取空后即退出（不清空未结算事件，避免丢掉已到手的应答）
        inbound.close()
        inboundConsumer = nil
        pendingExit = false
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
        try await callTool(name: toolName, arguments: arguments, timeout: nil)
    }

    /// 带**单次请求**超时的工具调用（D-22(a)：主题探测用短超时，避免一台不应答的服务器
    /// 把整条导入/卸载路径按配置默认 30s 拖住）。
    /// `timeout == nil` ⇒ 沿用 `config.requestTimeout`（既有语义逐字不变）。
    /// 超时由既有的 deadline 任务实现 ⇒ 到点即 `failPending`，不留挂起请求（不产生孤儿等待）。
    public func callTool(name toolName: String, arguments: [String: String], timeout: TimeInterval?) async throws -> String {
        try await start()
        let result = try await performRequest(method: "tools/call", params: [
            "name": toolName,
            "arguments": arguments,
        ], timeout: timeout)
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

    /// `timeout == nil` ⇒ 配置默认（`config.requestTimeout`）
    private func performRequest(method: String, params: [String: Any], timeout: TimeInterval? = nil) async throws -> [String: Any] {
        let json = try await rawRequest(method: method, params: params, timeout: timeout ?? config.requestTimeout)
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

    /// 子进程终止通知的**唯一投递点**（非隔离：Foundation 回调线程直接执行，零 Task hop）。
    ///
    /// ⚠️ 这里只允许「投递」，不允许任何结算：在本函数里直接 `failAllPending` 就是 D-25 的原缺陷
    ///    形状（独立 hop 与响应投递竞速 ⇒ 已到手的合法应答被吞）。判别器见
    ///    `MCPInboundFIFOTests.terminatingDuringSettlementDoesNotSwallowResponse`
    ///    （把本函数改回 `Task { await self.settle… }` 后该用例转红）。
    nonisolated func noteProcessTerminated() {
        inbound.append(.processExited)
    }

    /// 单一入站消费者（D-25(a2)）：行结算与退出清理在同一条串行队列上，顺序不再竞争
    private func consumeInbound() async {
        while let event = await inbound.next() {
            switch event {
            case let .line(line):
                await lineGateForTesting?(line)
                handleStdoutLine(line)
            case .readerEnded:
                readerStopped = true
                // 退出通知可能早于 EOF 到达：此时才做清理（行的结算已在上面全部完成）
                if pendingExit {
                    settleProcessExit()
                }
            case .processExited:
                pendingExit = true
                // 读端已 EOF ⇒ 已到手的应答全部结算完毕，立即清理
                if readerStopped {
                    settleProcessExit()
                }
            }
        }
    }

    /// 终止事件的清理（从 `processExited` 与 `readerEnded` 两个入口共用，幂等）
    private func settleProcessExit() {
        readerStopped = true
        pendingExit = false
        failAllPending(MCPError.transportClosed)
        started = false
        toolsCache = nil
        // 不清 `process` 引用：一是子进程已由 Foundation 回收（实测无僵尸），留着只是一枚已终止的
        //   Process 对象；二是若在「子进程死亡 → 本回调排队中 → 调用方已 relaunch」的窗口里清空，
        //   会把**新**进程的连接断掉（stop() 就不再 terminate 它 → 真孤儿）。生命周期随客户端注销
        //   （deinit 兜底 terminate）即可，正确性优先于省一枚对象。
    }

    /// 诊断用：最近 stderr 输出
    public var recentStderr: String {
        stderrLog
    }

    // MARK: 管道泵（独立线程阻塞读取，按行切分）

    /// stdout 泵：独立线程阻塞读取、按行切分；行与 EOF **同步**投递（D-25(a2) 的顺序前提）
    private static func pumpStdout(
        _ handle: FileHandle,
        onLine: @escaping @Sendable (String) -> Void,
        onEOF: @escaping @Sendable () -> Void
    ) {
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
                        onLine(line)
                    }
                }
            }
            // EOF / 读失败：终止哨兵排在全部数据行之后（见 InboundMailbox 存在理由）
            onEOF()
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
