import Foundation
import LLM
import ServiceContainer
import Session

public protocol Tool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameterSchema: String { get }
    var schema: ToolSchema { get }
    /// 必填参数名（执行器在调用前统一预校验；缺失 → invalid_args）
    var requiredParameters: [String] { get }
    /// 输出二次校验：true 时结果正文必须可解析为 JSON（否则 output_invalid）
    var validatesJSONOutput: Bool { get }
    func execute(_ args: [String: String], context: ToolRunContext) async throws -> ToolResult
}

public extension Tool {
    var schema: ToolSchema {
        ToolSchema(name: name, description: description, parameters: parameterSchema)
    }

    var requiredParameters: [String] {
        []
    }

    var validatesJSONOutput: Bool {
        false
    }
}

public struct ToolRunContext: @unchecked Sendable {
    public let signal: CancellationToken
    public let sessionID: SessionID
    public let metadata: [String: String]
    /// 流式进度回调（可选）：长耗时工具按块上报下载/执行进度
    public let onChunk: (@Sendable (String) -> Void)?
    /// 会话工作目录（P0.1.5 工作区接线：会话工作区 agents/\<sessionID\>；
    /// 文件工具相对路径与 exec 工作目录基于此解析；nil = 进程当前目录（旧行为））
    public let workingDirectory: URL?

    public init(signal: CancellationToken, sessionID: SessionID, metadata: [String: String],
                onChunk: (@Sendable (String) -> Void)? = nil, workingDirectory: URL? = nil) {
        self.signal = signal
        self.sessionID = sessionID
        self.metadata = metadata
        self.onChunk = onChunk
        self.workingDirectory = workingDirectory
    }
}

public struct ToolResult: Sendable {
    public let content: [LLM.ContentBlock]
    public let error: ToolError?
    public let meta: [String: String]?

    public init(content: [LLM.ContentBlock], error: ToolError? = nil, meta: [String: String]? = nil) {
        self.content = content
        self.error = error
        self.meta = meta
    }
}

public struct ToolError: Sendable, Error {
    public let name: String
    public let code: String
    public let message: String

    public init(name: String, code: String, message: String) {
        self.name = name
        self.code = code
        self.message = message
    }
}

public final class CancellationToken: @unchecked Sendable {
    private var _isCancelled: Bool = false
    public init() {}
    public var isCancelled: Bool {
        _isCancelled
    }

    public func cancel() {
        _isCancelled = true
    }
}

import Terminal

/// Tools 的取消信号桥接到 Terminal 包
extension CancellationToken: TerminalCancellationToken {}
