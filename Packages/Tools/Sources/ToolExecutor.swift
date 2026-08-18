import Foundation
import LLM
import ServiceContainer
import Session

// MARK: - 执行策略

/// 工具执行策略：超时 / 输出截断 / 熔断参数
public struct ToolExecutionPolicy: Sendable {
    /// 单次工具调用默认超时（秒）
    public var defaultTimeout: TimeInterval
    /// 按工具名覆盖超时（工具名 → 秒）
    public var timeouts: [String: TimeInterval]
    /// 文本输出字符上限：超限截断并追加标记（防大输出撑爆上下文/内存）
    public var maxOutputCharacters: Int
    /// 连续失败达此次数 → 熔断（open）
    public var breakerFailureThreshold: Int
    /// half-open 下连续成功达此次数 → 恢复（closed）
    public var breakerSuccessThreshold: Int
    /// open → half-open 的等待时长（秒）
    public var breakerResetTimeout: TimeInterval

    public init(defaultTimeout: TimeInterval = 60,
                timeouts: [String: TimeInterval] = [:],
                maxOutputCharacters: Int = 200_000,
                breakerFailureThreshold: Int = 5,
                breakerSuccessThreshold: Int = 3,
                breakerResetTimeout: TimeInterval = 30) {
        self.defaultTimeout = defaultTimeout
        self.timeouts = timeouts
        self.maxOutputCharacters = maxOutputCharacters
        self.breakerFailureThreshold = breakerFailureThreshold
        self.breakerSuccessThreshold = breakerSuccessThreshold
        self.breakerResetTimeout = breakerResetTimeout
    }
}

// MARK: - 错误与事件

/// 工具执行超时（调用侧任务已被取消；协作型工具应通过任务取消及时退出）
public struct ToolTimeoutError: Error, Sendable {
    public let timeout: TimeInterval
    public init(timeout: TimeInterval) {
        self.timeout = timeout
    }
}

/// 工具执行事件（可观测性 / UI 进度）
public enum ToolExecEvent: Sendable {
    case started(name: String)
    case finished(name: String, duration: TimeInterval, isError: Bool)
    case rejected(name: String, code: String)
}

// MARK: - 执行器

/// 工具执行器 — 工具调用的统一入口
///
/// 链路：工具查找 → 必填参数校验 → 按工具熔断 → 单次调用超时 → 执行 →
/// 输出二次校验（字符截断 / 可选 JSON 校验）→ 错误归一化回传。
///
/// 设计约束：
/// - 不抛异常给 Agent 主循环：所有失败都归一化为带 code 的 `ToolResult`，
///   由 Agent 回填为 tool 错误消息继续决策（避免单工具故障打死整个会话）；
/// - 超时不保证杀死不协作的工具任务（阻塞 I/O 可能残留到自然结束），
///   但 Agent 侧立即拿到 timeout 结果，不会悬挂。
public actor ToolExecutor {
    /// 事件回调（可选；在 actor 内触发）
    public nonisolated(unsafe) var onEvent: (@Sendable (ToolExecEvent) -> Void)?

    private let policy: ToolExecutionPolicy
    private var breakers: [String: CircuitBreaker] = [:]

    public init(policy: ToolExecutionPolicy = .init()) {
        self.policy = policy
    }

    /// 某工具的有效超时（按工具名覆盖 > 默认）
    public func timeout(for name: String) -> TimeInterval {
        policy.timeouts[name] ?? policy.defaultTimeout
    }

    /// 执行一次工具调用（统一返回 ToolResult；失败带 error.code）
    @discardableResult
    public func execute(_ call: ToolCall, in registry: ToolRegistry, context: ToolRunContext? = nil) async -> ToolResult {
        guard let tool = await registry.tool(named: call.name) else {
            let message = "工具不存在：\(call.name)"
            onEvent?(.rejected(name: call.name, code: "unknown_tool"))
            return ToolResult(content: [.text(message)],
                              error: ToolError(name: call.name, code: "unknown_tool", message: message))
        }
        let missing = tool.requiredParameters.filter { name in
            (call.arguments[name]?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty
        }
        if !missing.isEmpty {
            let message = "缺少必填参数：\(missing.joined(separator: ", "))"
            onEvent?(.rejected(name: tool.name, code: "invalid_args"))
            return ToolResult(content: [.text("错误：\(message)")],
                              error: ToolError(name: tool.name, code: "invalid_args", message: message))
        }

        let ctx = context ?? ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
        let timeout = timeout(for: tool.name)
        let start = Date()
        onEvent?(.started(name: tool.name))
        let result: ToolResult
        do {
            let executed = try await breaker(for: tool.name).call {
                try await withToolTimeout(timeout) {
                    try await tool.execute(call.arguments, context: ctx)
                }
            }
            result = sanitize(executed, tool: tool)
        } catch CircuitBreakerError.open {
            let message = "工具 \(tool.name) 已熔断（连续失败过多），暂时不可用"
            onEvent?(.rejected(name: tool.name, code: "circuit_open"))
            result = ToolResult(content: [.text(message)], error: ToolError(name: tool.name, code: "circuit_open", message: message))
        } catch is ToolTimeoutError {
            let seconds = Int(timeout.rounded(.up))
            let message = "工具 \(tool.name) 执行超时（\(seconds)s）"
            result = ToolResult(content: [.text(message)], error: ToolError(name: tool.name, code: "timeout", message: message))
        } catch {
            let message = "工具执行失败：\(error.localizedDescription)"
            result = ToolResult(content: [.text(message)], error: ToolError(name: tool.name, code: "exec_failed", message: error.localizedDescription))
        }
        onEvent?(.finished(name: tool.name, duration: Date().timeIntervalSince(start), isError: result.error != nil))
        return result
    }

    // MARK: 内部

    private func breaker(for name: String) -> CircuitBreaker {
        if let existing = breakers[name] {
            return existing
        }
        let breaker = CircuitBreaker(failureThreshold: policy.breakerFailureThreshold,
                                     successThreshold: policy.breakerSuccessThreshold,
                                     resetTimeout: policy.breakerResetTimeout)
        breakers[name] = breaker
        return breaker
    }

    /// 输出二次校验：可选 JSON 校验 + 字符数截断
    private func sanitize(_ result: ToolResult, tool: any Tool) -> ToolResult {
        if tool.validatesJSONOutput, result.error == nil {
            let text = Self.textOf(result.content).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                let data = Data(text.utf8)
                if (try? JSONSerialization.jsonObject(with: data)) == nil {
                    let message = "输出校验失败：工具 \(tool.name) 的正文不是合法 JSON"
                    return ToolResult(content: [.text(message)],
                                      error: ToolError(name: tool.name, code: "output_invalid", message: message))
                }
            }
        }
        let limit = policy.maxOutputCharacters
        let total = Self.textCharCount(result.content)
        guard total > limit else {
            return result
        }
        var carried = 0
        var didTruncate = false
        let trimmed = result.content.map { block -> LLM.ContentBlock in
            guard case let .text(text) = block else {
                return block
            }
            let remaining = max(0, limit - carried)
            guard text.count > remaining else {
                carried += text.count
                return block
            }
            didTruncate = true
            carried += remaining
            return .text(String(text.prefix(remaining)) + "\n[输出截断：共 \(total) 字符，保留前 \(remaining)]")
        }
        guard didTruncate else {
            return result
        }
        var meta = result.meta ?? [:]
        meta["truncated"] = "true"
        return ToolResult(content: trimmed, error: result.error, meta: meta)
    }

    static func textOf(_ blocks: [LLM.ContentBlock]) -> String {
        blocks.compactMap { block -> String? in
            if case let .text(s) = block {
                return s
            }
            return nil
        }.joined()
    }

    static func textCharCount(_ blocks: [LLM.ContentBlock]) -> Int {
        blocks.reduce(0) { sum, block in
            if case let .text(s) = block {
                return sum + s.count
            }
            return sum
        }
    }
}

// MARK: - 有界执行

/// 限时执行：到点立即抛 `ToolTimeoutError` 并取消运行中任务
///
/// 语义：原操作先完成 → 原样返回/抛出；定时器先完成 → 抛超时并取消操作。
public func withToolTimeout<T: Sendable>(
    _ seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: ToolTimeoutRace<T>.self) { group in
        group.addTask {
            do {
                return try await .value(operation())
            } catch {
                throw error
            }
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            return .timedOut
        }
        guard let first = try await group.next() else {
            throw ToolTimeoutError(timeout: seconds)
        }
        group.cancelAll()
        switch first {
        case let .value(value):
            return value
        case .timedOut:
            throw ToolTimeoutError(timeout: seconds)
        }
    }
}

/// 限时执行竞速结果
private enum ToolTimeoutRace<T: Sendable>: Sendable {
    case value(T)
    case timedOut
}
