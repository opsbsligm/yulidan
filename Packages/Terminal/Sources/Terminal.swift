import Foundation

// MARK: - 取消信号

/// 取消信号协议（Tools 包的 CancellationToken 可桥接实现）
public protocol TerminalCancellationToken: Sendable {
    var isCancelled: Bool { get }
}

// MARK: - 配置与结果

/// 终端执行配置
public struct TerminalConfiguration: Sendable {
    /// shell 可执行文件路径
    public var shellPath: String
    /// shell 启动参数（命令会追加在最后）
    public var shellArguments: [String]
    /// 工作目录（nil = 继承）
    public var workingDirectory: String?
    /// 附加环境变量（覆盖继承环境）
    public var environment: [String: String]?
    /// 超时秒数
    public var timeout: TimeInterval
    /// stdout/stderr 各自最多捕获字节数（防止失控命令撑爆内存）
    public var maxCaptureBytes: Int
    /// 最终展示文本截断长度（字符）
    public var maxOutputCharacters: Int

    public init(shellPath: String = "/bin/zsh",
                shellArguments: [String] = ["-c"],
                workingDirectory: String? = nil,
                environment: [String: String]? = nil,
                timeout: TimeInterval = 30,
                maxCaptureBytes: Int = 2_000_000,
                maxOutputCharacters: Int = 50000) {
        self.shellPath = shellPath
        self.shellArguments = shellArguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeout = timeout
        self.maxCaptureBytes = maxCaptureBytes
        self.maxOutputCharacters = maxOutputCharacters
    }
}

/// 一次终端执行的结果
public struct TerminalRunResult: Sendable {
    public let command: String
    public let stdout: String
    public let stderr: String
    public let terminationStatus: Int32
    public let timedOut: Bool
    public let cancelled: Bool
    public let duration: TimeInterval

    /// 合并 stdout/stderr（无输出时占位）
    public var combinedOutput: String {
        var s = ""
        if !stdout.isEmpty {
            s = stdout
        }
        if !stderr.isEmpty {
            s += (s.isEmpty ? "" : "\n") + "[stderr]\n" + stderr
        }
        if s.isEmpty {
            s = "（无输出）"
        }
        return s
    }

    /// UI 展示文本：退出码 + 合并输出，截断至 maxCharacters
    public func displayString(maxCharacters: Int) -> String {
        var note = "退出码 \(terminationStatus)"
        if timedOut {
            note += "（超时被终止）"
        }
        if cancelled {
            note += "（已取消）"
        }
        return String(("✅ \(note)\n\n" + combinedOutput).prefix(maxCharacters))
    }
}

/// 终端错误
public enum TerminalError: Error, Sendable, CustomStringConvertible {
    /// 无法启动 shell（如 shellPath 不存在）
    case launchFailed(String)

    public var description: String {
        switch self {
        case let .launchFailed(reason):
            "终端启动失败：\(reason)"
        }
    }
}

// MARK: - TerminalRunner

/// 通用 shell 命令执行器
///
/// 实现说明：
/// - stdout/stderr 在两个独立线程并行分块读取，避免管道缓冲区写满导致死锁；
/// - 主循环每 50ms 轮询一次：命中超时或取消信号即 terminate；
/// - 捕获字节数超过 maxCaptureBytes 后停止读取（进程会在超时/取消时被终止）。
public struct TerminalRunner: Sendable {
    public let configuration: TerminalConfiguration

    public init(configuration: TerminalConfiguration = TerminalConfiguration()) {
        self.configuration = configuration
    }

    /// 执行命令并等待结束（带超时与取消）
    /// - Parameter command: 传给 shell 的完整命令
    /// - Parameter signal: 可选取消信号；已取消时立即返回 cancelled 结果
    public func run(_ command: String, signal: (any TerminalCancellationToken)? = nil) async throws -> TerminalRunResult {
        let started = Date()
        if signal?.isCancelled == true {
            return TerminalRunResult(command: command, stdout: "", stderr: "", terminationStatus: -1,
                                     timedOut: false, cancelled: true, duration: 0)
        }

        return try await withCheckedThrowingContinuation { cont in
            let process = Process()
            let outPipe = Pipe()
            let errPipe = Pipe()
            let group = DispatchGroup()
            let box = RunBox(process: process,
                             outPipe: outPipe,
                             errPipe: errPipe,
                             group: group,
                             maxCaptureBytes: configuration.maxCaptureBytes)

            startReaders(box: box, group: group)
            configure(process, command: command, outPipe: outPipe, errPipe: errPipe)

            do {
                try process.run()
            } catch {
                box.stopped = true
                // 关闭管道写端：让读取线程读到 EOF 退出，避免 group.wait() 死锁
                try? outPipe.fileHandleForWriting.close()
                try? errPipe.fileHandleForWriting.close()
                group.wait()
                cont.resume(throwing: TerminalError.launchFailed(error.localizedDescription))
                return
            }

            // 轮询：超时 / 取消 → terminate
            let (timedOut, cancelled) = pollUntilExit(process: process, signal: signal, timeout: configuration.timeout)
            box.stopped = true
            process.waitUntilExit()
            group.wait()

            let result = TerminalRunResult(
                command: command,
                stdout: Self.decode(box.outData),
                stderr: Self.decode(box.errData),
                terminationStatus: process.terminationStatus,
                timedOut: timedOut,
                cancelled: cancelled,
                duration: Date().timeIntervalSince(started)
            )
            cont.resume(returning: result)
        }
    }

    /// UTF-8 解码（失败时 lossy 兜底）
    private static func decode(_ data: Data) -> String {
        if let text = String(bytes: data, encoding: .utf8) {
            return text
        }
        // 非 UTF-8 输出需要 lossy 兜底（String(decoding:) 为唯一安全 lossy API），故豁免该规则
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: data, as: UTF8.self)
    }

    /// 启动 stdout/stderr 并行读取线程
    private func startReaders(box: RunBox, group: DispatchGroup) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            box.outData = Self.readAll(box.outPipe.fileHandleForReading, box: box)
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            box.errData = Self.readAll(box.errPipe.fileHandleForReading, box: box)
            group.leave()
        }
    }

    /// 按配置填充 Process（shell / 参数 / 管道 / 工作目录 / 环境变量）
    private func configure(_ process: Process, command: String, outPipe: Pipe, errPipe: Pipe) {
        process.executableURL = URL(fileURLWithPath: configuration.shellPath)
        process.arguments = configuration.shellArguments + [command]
        process.standardOutput = outPipe
        process.standardError = errPipe
        if let wd = configuration.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: (wd as NSString).expandingTildeInPath)
        }
        if let env = configuration.environment {
            process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        }
    }

    /// 每 50ms 轮询进程状态；超时或取消时 terminate。返回 (timedOut, cancelled)
    private func pollUntilExit(process: Process, signal: (any TerminalCancellationToken)?, timeout: TimeInterval) -> (Bool, Bool) {
        var timedOut = false
        var cancelled = false
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if let signal, signal.isCancelled {
                cancelled = true
                process.terminate()
                break
            }
            if Date() > deadline {
                timedOut = true
                process.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return (timedOut, cancelled)
    }

    /// 分块读取管道至 EOF 或达到上限（达到上限后停止读取，进程后续由超时/取消终止）
    private static func readAll(_ handle: FileHandle, box: RunBox) -> Data {
        var data = Data()
        while !box.stopped {
            let remaining = box.maxCaptureBytes - data.count
            if remaining <= 0 {
                break
            }
            let chunk = (try? handle.read(upToCount: min(65536, remaining))) ?? Data()
            if chunk.isEmpty {
                break
            }
            data.append(chunk)
        }
        return data
    }

    /// @unchecked Sendable 盒子：把 Process/Pipe 传给 @Sendable 闭包
    private final class RunBox {
        let process: Process
        let outPipe: Pipe
        let errPipe: Pipe
        let group: DispatchGroup
        let maxCaptureBytes: Int
        var outData = Data()
        var errData = Data()
        var stopped = false
        init(process: Process, outPipe: Pipe, errPipe: Pipe, group: DispatchGroup, maxCaptureBytes: Int) {
            self.process = process
            self.outPipe = outPipe
            self.errPipe = errPipe
            self.group = group
            self.maxCaptureBytes = maxCaptureBytes
        }
    }
}
