import Darwin
import Foundation

// MARK: - 错误

public enum SocketError: Error, Sendable {
    case socketCreateFailed(Int32)
    case invalidHost
    case bindFailed(Int32)
    case listenFailed(Int32)
    case writeFailed(Int32)
    case readFailed(Int32)
}

/// 请求体超出上限
public struct BodyTooLargeError: Error, Sendable {}

// MARK: - 服务器

/// 极简 HTTP/1.1 服务器（本地开发用，零外部依赖）
///
/// - POSIX socket 实现，每条连接处理一个请求（`Connection: close` 语义）
/// - 阻塞 syscall（accept/read/write）一律在 GCD 全局队列执行，
///   通过 continuation 桥接回 async —— **不占用 Swift 协作线程池**，
///   避免并发多服务器/多连接时耗尽协作线程造成死锁（P0 修复，2026-08-18）
/// - 默认仅绑定 127.0.0.1；`port: 0` 时由内核分配临时端口（测试用）
///
/// ⚠️ 面向本地开发场景（`dsh web`），非生产服务器：无 TLS、无 keep-alive。
public final class MiniHTTPServer: @unchecked Sendable {
    /// 请求处理器：入站请求 → 出站响应
    public typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    private let host: String
    private let port: UInt16
    private let handler: Handler
    private let maxHeadBytes: Int
    private let maxBodyBytes: Int
    private let readTimeout: TimeInterval
    private let activeHolder = ActiveFDs()

    private let stopGate = StopGate()
    private var listenFD: Int32 = -1
    private var acceptTask: Task<Void, Never>?

    /// 回环地址绑定失败（EADDRNOTAVAIL，部分虚拟化环境限制）时是否回退到了 0.0.0.0
    public private(set) var fellBackToAnyInterface = false

    public init(
        host: String = "127.0.0.1",
        port: UInt16 = 0,
        maxHeadBytes: Int = 65536,
        maxBodyBytes: Int = 1_048_576,
        readTimeout: TimeInterval = 30,
        handler: @escaping Handler
    ) {
        self.host = host
        self.port = port
        self.handler = handler
        self.maxHeadBytes = maxHeadBytes
        self.maxBodyBytes = maxBodyBytes
        self.readTimeout = readTimeout
    }

    /// 启动服务器，返回实际监听端口（port 为 0 时为内核分配的临时端口）
    @discardableResult
    public func start() async throws -> UInt16 {
        guard stopGate.isStopped == false else {
            throw SocketError.bindFailed(0)
        }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw SocketError.socketCreateFailed(errno)
        }

        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        let loopback = in_addr(s_addr: INADDR_LOOPBACK)
        let anyInterface = in_addr(s_addr: INADDR_ANY)
        var target: in_addr
        switch host {
        case "0.0.0.0":
            target = anyInterface
        case "127.0.0.1", "localhost":
            target = loopback
        default:
            var inet = in_addr()
            guard inet_aton(host, &inet) != 0 else {
                Darwin.close(fd)
                throw SocketError.invalidHost
            }
            target = inet
        }

        var bound = bindSocket(fd, port: port, address: target)
        // 部分虚拟化环境禁止绑定回环地址（EADDRNOTAVAIL）：回退到 0.0.0.0（连接 127.0.0.1 仍可达）
        if bound != 0, target.s_addr == loopback.s_addr, errno == EADDRNOTAVAIL {
            fellBackToAnyInterface = true
            bound = bindSocket(fd, port: port, address: anyInterface)
        }
        guard bound == 0 else {
            let code = errno
            Darwin.close(fd)
            throw SocketError.bindFailed(code)
        }
        guard Darwin.listen(fd, 16) == 0 else {
            let code = errno
            Darwin.close(fd)
            throw SocketError.listenFailed(code)
        }

        // 取实际绑定端口（port=0 时由内核分配）
        var actual = sockaddr_in()
        var addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let resolved = withUnsafeMutablePointer(to: &actual) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(fd, sockaddrPointer, &addressLength)
            }
        }
        let actualPort = resolved == 0 ? UInt16(bigEndian: actual.sin_port) : port

        listenFD = fd
        acceptTask = Task { [weak self] in
            await self?.acceptLoop(fd: fd)
        }
        return actualPort
    }

    private func bindSocket(_ fd: Int32, port: UInt16, address: in_addr) -> Int32 {
        var sockaddrIn = sockaddr_in()
        sockaddrIn.sin_family = sa_family_t(AF_INET)
        sockaddrIn.sin_port = port.bigEndian
        sockaddrIn.sin_addr = address
        return withUnsafePointer(to: &sockaddrIn) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    /// 停止服务器：关闭监听 socket 与全部在途连接
    ///
    /// 阻塞 I/O 在 GCD 线程执行：close 后立即返回错误，
    /// accept 循环经 500ms 轮询检测到停止标记后退出。
    public func stop() async {
        stopGate.markStopped()
        if listenFD >= 0 {
            let fd = listenFD
            listenFD = -1
            Darwin.close(fd)
        }
        activeHolder.closeAll()
        if let task = acceptTask {
            task.cancel()
            acceptTask = nil
        }
    }

    // MARK: - 阻塞 I/O 桥接（GCD 全局队列，不占协作线程池）

    /// 在 GCD 全局队列执行阻塞操作，挂起当前任务等待结果
    private func blocking<T: Sendable>(_ op: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = op()
                continuation.resume(returning: result)
            }
        }
    }

    /// 单次 accept（GCD 线程内 poll 轮询；返回 nil 表示已停止，-1 表示监听异常退出）
    private func acceptOnce(fd: Int32) async -> Int32? {
        let gate = stopGate
        return await blocking {
            while true {
                var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let ready = poll(&pfd, 1, 500)
                if ready > 0 {
                    let clientFD = accept(fd, nil, nil)
                    if clientFD >= 0 {
                        return clientFD
                    }
                    let code = errno
                    if code == EAGAIN || code == EWOULDBLOCK || code == EINTR {
                        continue
                    }
                    return -1 // 其他错误（含 fd 已关闭）：退出
                }
                if ready < 0, errno != EINTR {
                    return -1
                }
                // 轮询超时：检查停止标记（close 不保证唤醒阻塞的 accept）
                if gate.isStopped {
                    return nil
                }
            }
        }
    }

    /// 读取一段数据（GCD 线程执行阻塞 read），返回 (字节数, 缓冲区)
    private func readChunk(fd: Int32, count: Int) async -> (Int, [UInt8]) {
        await blocking {
            var chunk = [UInt8](repeating: 0, count: count)
            let n = read(fd, &chunk, count)
            return (n, chunk)
        }
    }

    // MARK: - 连接循环

    private func acceptLoop(fd: Int32) async {
        while stopGate.isStopped == false, !Task.isCancelled {
            let clientFD = await acceptOnce(fd: fd)
            guard let clientFD else {
                break // 服务器已停止
            }
            if clientFD < 0 {
                break // 监听 socket 异常
            }
            activeHolder.insert(clientFD)
            Task { [weak self] in
                defer { self?.activeHolder.remove(clientFD) }
                await self?.handleConnection(clientFD)
            }
        }
    }

    private func handleConnection(_ fd: Int32) async {
        // 读写超时：防止半开连接永久占用 GCD 线程
        var timeout = timeval(tv_sec: Int(readTimeout), tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        defer { Darwin.close(fd) }

        do {
            let request = try await readRequest(fd: fd)
            guard !request.method.isEmpty else {
                return // 连接直接断开，无需响应
            }
            let response = await handler(request)
            try await writeResponse(fd: fd, response: response)
        } catch {
            let fallback: HTTPResponse
            if let httpError = error as? HTTPError {
                fallback = .badRequest(Self.httpErrorMessage(for: httpError))
            } else if let socketError = error as? SocketError, case .writeFailed = socketError {
                // 对端已断开，无响应可写
                return
            } else if error is BodyTooLargeError {
                fallback = .tooLarge()
            } else {
                fallback = .serverError("internal error")
            }
            try? await writeResponse(fd: fd, response: fallback)
        }
    }

    /// 读取完整请求（头 + 声明长度的正文）
    private func readRequest(fd: Int32) async throws -> HTTPRequest {
        let (headText, bodyPrefix) = try await readHead(fd: fd)
        guard !headText.isEmpty else {
            // 对端断开或读超时：无请求行
            return HTTPRequest(method: "", path: "", query: [:], headers: [:], body: Data())
        }
        var request = try HTTPRequest.parseHead(headText, bodyPrefix: bodyPrefix)
        guard !request.method.isEmpty else {
            return request
        }
        request.body = try await readBody(fd: fd, request: request, current: request.body)
        return request
    }

    /// 读取请求头（截至 \r\n\r\n），返回 (头文本, 随头到达的正文前缀)；头为空表示对端已断开
    private func readHead(fd: Int32) async throws -> (String, Data) {
        var headData = Data()
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])
        while headData.range(of: separator) == nil {
            guard headData.count < maxHeadBytes else {
                throw HTTPError.oversizedHead
            }
            let (readCount, chunk) = await readChunk(fd: fd, count: 8192)
            guard readCount > 0 else {
                return ("", Data())
            }
            headData.append(contentsOf: chunk[0 ..< readCount])
        }
        let separatorRange = headData.range(of: separator)
        guard let separatorRange else {
            throw HTTPError.badRequestLine
        }
        let headEnd = separatorRange.upperBound
        // 头部（含空行）总长不得超过上限：无论一次到达还是分片到达都拒绝
        guard headData.distance(from: headData.startIndex, to: headEnd) <= maxHeadBytes else {
            throw HTTPError.oversizedHead
        }
        let headSlice = Data(headData[0 ..< headEnd])
        guard let headText = String(data: headSlice, encoding: .utf8) else {
            throw HTTPError.badRequestLine
        }
        return (headText, Data(headData[headEnd...]))
    }

    /// 按 Content-Length 补齐正文（已有前缀时继续读取）
    private func readBody(fd: Int32, request: HTTPRequest, current: Data) async throws -> Data {
        let wanted = request.contentLength
        guard wanted <= maxBodyBytes else {
            throw BodyTooLargeError()
        }
        var body = current
        while body.count < wanted {
            let (readCount, chunk) = await readChunk(fd: fd, count: 8192)
            guard readCount > 0 else {
                throw HTTPError.badRequestLine
            }
            body.append(contentsOf: chunk[0 ..< readCount])
        }
        guard body.count > wanted else {
            return body
        }
        return Data(body[0 ..< wanted])
    }

    /// 完整写出响应（GCD 线程执行阻塞 write）
    private func writeResponse(fd: Int32, response: HTTPResponse) async throws {
        let data = response.render()
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let slice = bytes[offset...]
            let written = await blocking {
                slice.withUnsafeBufferPointer { buffer -> Int in
                    guard let base = buffer.baseAddress else { return 0 }
                    return Darwin.write(fd, base, buffer.count)
                }
            }
            guard written > 0 else {
                throw SocketError.writeFailed(errno)
            }
            offset += written
        }
    }

    static func httpErrorMessage(for error: HTTPError) -> String {
        switch error {
        case .badRequestLine: "bad request line"
        case .badHeaderLine: "bad header line"
        case .oversizedHead: "request head too large"
        }
    }
}

/// 活跃连接 fd 集合（stop 时统一关闭，打断进行中的阻塞 read）
final class ActiveFDs: @unchecked Sendable {
    private let lock = NSLock()
    private var fds: Set<Int32> = []

    func insert(_ fd: Int32) {
        lock.lock()
        defer { lock.unlock() }
        fds.insert(fd)
    }

    @discardableResult
    func remove(_ fd: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return fds.remove(fd) != nil
    }

    func closeAll() {
        lock.lock()
        let all = fds
        fds.removeAll()
        lock.unlock()
        for fd in all {
            Darwin.close(fd)
        }
    }
}

/// 停止标记（NSLock 保护，信号/线程安全）
private final class StopGate: @unchecked Sendable {
    private let lock = NSLock()
    private var stoppedFlag = false

    var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stoppedFlag
    }

    func markStopped() {
        lock.lock()
        stoppedFlag = true
        lock.unlock()
    }
}
