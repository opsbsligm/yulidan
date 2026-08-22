import Foundation
import LLM
import Sandbox
import ServiceContainer
import Terminal

// 内置真实工具集 — 供 ToolRegistry 注册后在 UI 中真实执行
// ⚠️ 安全提示：exec_command / write_file 具备真实执行能力，生产环境接入前
//    建议叠加沙箱（Packages/Sandbox）与权限确认。

// MARK: - 沙箱守卫

enum SandboxGuard {
    static func reject(_ tool: String, _ path: String) -> ToolResult {
        ToolResult(content: [.text("❌ 路径超出沙箱允许范围：\(path)")],
                   error: ToolError(name: tool, code: "outside_sandbox", message: "路径超出沙箱允许范围"))
    }
}

/// 解析工具路径（P0.1.5 会话工作区接线）：绝对路径 / ~ 路径原样；
/// 相对路径基于会话工作目录解析（未提供时保持进程 cwd 旧行为）。
/// 注意：必须先解析再沙箱校验，防止相对路径绕过沙箱。
func resolveToolPath(_ raw: String, workingDirectory: URL?) -> String {
    let expanded = (raw as NSString).expandingTildeInPath
    if (expanded as NSString).isAbsolutePath {
        return expanded
    }
    if let workingDirectory {
        return workingDirectory.appendingPathComponent(expanded).standardizedFileURL.path
    }
    return expanded
}

// MARK: - read_file

public struct ReadFileTool: Tool {
    /// 可选路径沙箱；注入后越界路径返回 outside_sandbox 错误
    public let sandbox: PathSandbox?

    public init(sandbox: PathSandbox? = nil) {
        self.sandbox = sandbox
    }

    public let name = "read_file"
    public let description = "读取文件内容（默认限制 200KB）"
    public let parameterSchema = "{\"path\": \"文件路径（绝对，或相对当前会话工作区）\"}"
    public let requiredParameters = ["path"]

    public func execute(_ args: [String: String], context: ToolRunContext) async throws -> ToolResult {
        guard let path = args["path"]?.trimmingCharacters(in: .whitespaces), !path.isEmpty else {
            return ToolResult(content: [.text("错误：缺少参数 path")],
                              error: ToolError(name: "read_file", code: "missing_arg", message: "缺少 path 参数"))
        }
        // 先基于会话工作目录解析相对路径，再沙箱校验（防相对路径绕过）
        let resolved = resolveToolPath(path, workingDirectory: context.workingDirectory)
        if let sandbox {
            do {
                try sandbox.assertAllowed(resolved)
            } catch {
                return SandboxGuard.reject("read_file", resolved)
            }
        }
        let url = URL(fileURLWithPath: resolved)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ToolResult(content: [.text("错误：文件不存在 \(url.path)")],
                              error: ToolError(name: "read_file", code: "not_found", message: "文件不存在"))
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs[.size] as? Int ?? 0
        guard size < 200_000 else {
            return ToolResult(content: [.text("文件过大（\(size) 字节），超过 200KB 限制，拒绝读取。")])
        }
        let data = try Data(contentsOf: url)
        if let text = String(data: data, encoding: .utf8) {
            return ToolResult(content: [.text("✅ 已读取 \(url.path)（\(size) 字节）\n\n\(text)")],
                              error: nil, meta: ["path": url.path, "bytes": "\(size)"])
        }
        let out = "该文件不是 UTF-8 文本（\(size) 字节），已跳过内容。"
        return ToolResult(content: [.text(out)],
                          meta: ["path": url.path])
    }
}

// MARK: - write_file

public struct WriteFileTool: Tool {
    /// 可选路径沙箱；注入后越界路径返回 outside_sandbox 错误
    public let sandbox: PathSandbox?

    public init(sandbox: PathSandbox? = nil) {
        self.sandbox = sandbox
    }

    public let name = "write_file"
    public let description = "写入文件内容（目录不存在时自动创建）"
    public let parameterSchema = "{\"path\": \"文件路径（绝对，或相对当前会话工作区）\", \"content\": \"要写入的内容\"}"
    public let requiredParameters = ["path"]

    public func execute(_ args: [String: String], context: ToolRunContext) async throws -> ToolResult {
        guard let path = args["path"]?.trimmingCharacters(in: .whitespaces), !path.isEmpty else {
            return ToolResult(content: [.text("错误：缺少参数 path")],
                              error: ToolError(name: "write_file", code: "missing_arg", message: "缺少 path 参数"))
        }
        // 先基于会话工作目录解析相对路径，再沙箱校验（防相对路径绕过）
        let resolved = resolveToolPath(path, workingDirectory: context.workingDirectory)
        if let sandbox {
            do {
                try sandbox.assertAllowed(resolved)
            } catch {
                return SandboxGuard.reject("write_file", resolved)
            }
        }
        let content = args["content"] ?? ""
        let url = URL(fileURLWithPath: resolved)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try content.data(using: .utf8)!.write(to: url, options: .atomic)
            let out = "✅ 已写入 \(url.path)（\(content.count) 字符）"
            return ToolResult(content: [.text(out)],
                              meta: ["path": url.path, "chars": "\(content.count)"])
        } catch {
            return ToolResult(content: [.text("❌ 写入失败：\(error.localizedDescription)")],
                              error: ToolError(name: "write_file", code: "write_failed", message: error.localizedDescription))
        }
    }
}

// MARK: - list_files

public struct ListFilesTool: Tool {
    /// 可选路径沙箱；注入后越界路径返回 outside_sandbox 错误
    public let sandbox: PathSandbox?

    public init(sandbox: PathSandbox? = nil) {
        self.sandbox = sandbox
    }

    public let name = "list_files"
    public let description = "列出目录下的文件与子目录"
    public let parameterSchema = "{\"path\": \"目录路径（绝对，或相对当前会话工作区），缺省 = 会话工作区根\", \"limit\": \"最多显示条数，默认 100\"}"

    public func execute(_ args: [String: String], context: ToolRunContext) async throws -> ToolResult {
        let rawPath = (args["path"] ?? ".").trimmingCharacters(in: .whitespaces)
        // 先基于会话工作目录解析相对路径（缺省 "." = 工作目录本身），再沙箱校验
        let resolved = resolveToolPath(rawPath, workingDirectory: context.workingDirectory)
        if let sandbox {
            do {
                try sandbox.assertAllowed(resolved)
            } catch {
                return SandboxGuard.reject("list_files", resolved)
            }
        }
        let url = URL(fileURLWithPath: resolved)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return ToolResult(content: [.text("错误：目录不存在 \(url.path)")],
                              error: ToolError(name: "list_files", code: "not_found", message: "目录不存在"))
        }
        guard isDir.boolValue else {
            return ToolResult(content: [.text("错误：\(url.path) 不是目录")])
        }
        let limit = Int(args["limit"] ?? "100") ?? 100
        do {
            let entries = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .prefix(limit)
            var lines: [String] = []
            for e in entries {
                let vals = try e.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                let mark = vals.isDirectory == true ? "📁 " : "   "
                let size = vals.fileSize.map { "  (\(Self.sizeStr($0)))" } ?? ""
                lines.append("\(mark)\(e.lastPathComponent)\(size)")
            }
            return ToolResult(content: [.text("✅ \(url.path) 共 \(entries.count) 项（显示前 \(entries.count > limit ? limit : entries.count) 项）\n" + lines.joined(separator: "\n"))],
                              meta: ["path": url.path, "count": "\(entries.count)"])
        } catch {
            return ToolResult(content: [.text("❌ 读取目录失败：\(error.localizedDescription)")],
                              error: ToolError(name: "list_files", code: "read_failed", message: error.localizedDescription))
        }
    }

    static func sizeStr(_ n: Int) -> String {
        if n < 1024 {
            return "\(n)B"
        }
        if n < 1024 * 1024 {
            return String(format: "%.1fKB", Double(n) / 1024)
        }
        return String(format: "%.1fMB", Double(n) / 1024 / 1024)
    }
}

// MARK: - exec_command

public struct ExecCommandTool: Tool {
    public let runner: TerminalRunner

    public init(runner: TerminalRunner = TerminalRunner()) {
        self.runner = runner
    }

    public let name = "exec_command"
    public let description = "在系统 shell 中执行命令并返回输出（工作目录默认为当前会话工作区；⚠️ 具备真实执行能力，请谨慎）"
    public let parameterSchema = "{\"cmd\": \"要执行的 shell 命令\", \"timeout\": \"超时秒数，默认 30\"}"
    public let requiredParameters = ["cmd"]

    public func execute(_ args: [String: String], context: ToolRunContext) async throws -> ToolResult {
        guard let cmd = args["cmd"]?.trimmingCharacters(in: .whitespaces), !cmd.isEmpty else {
            return ToolResult(content: [.text("错误：缺少参数 cmd")],
                              error: ToolError(name: "exec_command", code: "missing_arg", message: "缺少 cmd 参数"))
        }
        // 支持按次覆盖超时（工具层配置，runner 默认 30s）
        var config = runner.configuration
        if let t = Double(args["timeout"] ?? "") {
            config.timeout = t
        }
        // 会话工作区接线：runner 未设默认工作目录时，exec 工作目录 = 会话工作目录
        if config.workingDirectory == nil, let wd = context.workingDirectory {
            config.workingDirectory = wd.path
        }
        do {
            let result = try await TerminalRunner(configuration: config).run(cmd, signal: context.signal)
            return ToolResult(content: [.text(result.displayString(maxCharacters: config.maxOutputCharacters))],
                              error: nil,
                              meta: ["cmd": String(cmd.prefix(200)),
                                     "exit": String(result.terminationStatus),
                                     "timed_out": String(result.timedOut),
                                     "cancelled": String(result.cancelled)])
        } catch {
            return ToolResult(content: [.text("❌ 命令执行失败：\(error.localizedDescription)")],
                              error: ToolError(name: "exec_command", code: "exec_failed", message: error.localizedDescription))
        }
    }
}

// MARK: - web_fetch

/// 网页抓取：GET http/https，返回正文文本（字节上限 + 字符截断）
///
/// 安全约束：
/// - 仅允许 http/https 协议；
/// - 响应超过 `maxBytes` 直接拒绝（防大文件撑爆内存）；
/// - 文本超过 `max_chars` 截断（默认 20000 字符）。
public struct WebFetchTool: Tool {
    public let name = "web_fetch"
    public let description = "抓取 http/https 网页并返回文本内容（超限截断；分块流式下载并上报进度）"
    public let parameterSchema = "{\"url\": \"网页地址\", \"max_chars\": \"最多返回字符数，默认 20000\"}"
    public let requiredParameters = ["url"]

    private let session: URLSession
    private let maxBytes: Int
    private let timeout: TimeInterval

    public init(session: URLSession = .shared, maxBytes: Int = 512_000, timeout: TimeInterval = 30) {
        self.session = session
        self.maxBytes = maxBytes
        self.timeout = timeout
    }

    enum FetchError: Error {
        case badResponse
        case http(Int)
        case tooLarge
        case failed(String)
    }

    public func execute(_ args: [String: String], context: ToolRunContext) async throws -> ToolResult {
        guard let raw = args["url"]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return ToolResult(content: [.text("错误：缺少参数 url")],
                              error: ToolError(name: name, code: "missing_arg", message: "缺少 url 参数"))
        }
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return ToolResult(content: [.text("错误：仅支持 http/https 地址：\(raw)")],
                              error: ToolError(name: name, code: "bad_url", message: "不支持的协议"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Harness/0.1",
                         forHTTPHeaderField: "User-Agent")
        let (data, status): (Data, Int)
        do {
            (data, status) = try await download(request, onChunk: context.onChunk)
        } catch let error as FetchError {
            switch error {
            case .badResponse:
                return ToolResult(content: [.text("❌ 无法解析 HTTP 响应")],
                                  error: ToolError(name: name, code: "fetch_failed", message: "无法解析响应"))
            case let .http(code):
                return ToolResult(content: [.text("❌ HTTP \(code)")],
                                  error: ToolError(name: name, code: "http_error", message: "HTTP \(code)"))
            case .tooLarge:
                return ToolResult(content: [.text("内容过大（>\(maxBytes) 字节），超过 \(maxBytes) 字节限制，拒绝抓取。")],
                                  error: ToolError(name: name, code: "too_large", message: "内容超过字节上限"))
            case let .failed(message):
                return ToolResult(content: [.text("❌ 抓取失败：\(message)")],
                                  error: ToolError(name: name, code: "fetch_failed", message: message))
            }
        } catch {
            var hint = ""
            if let urlError = error as? URLError, urlError.code == .timedOut {
                hint = "（超时）"
            }
            let msg = error.localizedDescription + hint
            return ToolResult(content: [.text("❌ 抓取失败：\(msg)")],
                              error: ToolError(name: name, code: "fetch_failed", message: msg))
        }
        // UTF-8 优先，失败回退 ISO-8859-1（任意字节可解码，保内容不丢失）
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let maxChars = Int(args["max_chars"] ?? "") ?? 20000
        let truncated = text.count > maxChars
        let shown = String(text.prefix(maxChars))
        return ToolResult(content: [.text("✅ 已抓取 \(url.absoluteString)（\(data.count) 字节，HTTP \(status)）\n\n\(shown)")],
                          error: nil,
                          meta: ["url": url.absoluteString,
                                 "bytes": "\(data.count)",
                                 "status": "\(status)",
                                 "truncated": String(truncated)])
    }

    /// 分块流式下载：每 64KB 上报一次进度；累计超过字节上限立即中止
    private func download(_ request: URLRequest,
                          onChunk: (@Sendable (String) -> Void)?) async throws -> (Data, Int) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FetchError.badResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw FetchError.http(http.statusCode)
        }
        var data = Data()
        var lastReportedKB = 0
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxBytes {
                    throw FetchError.tooLarge
                }
                let kb = data.count / 1024
                if kb >= lastReportedKB + 64 {
                    lastReportedKB = kb
                    onChunk?("已下载 \(kb) KB")
                }
            }
        } catch let error as FetchError {
            throw error
        } catch {
            throw FetchError.failed(error.localizedDescription)
        }
        return (data, http.statusCode)
    }
}

// MARK: - 注册辅助

public enum BuiltinTools {
    /// 创建全部内置工具实例（不带沙箱，兼容既有调用）
    public static func makeAll() -> [any Tool] {
        makeAll(sandbox: nil)
    }

    /// 创建全部内置工具实例；注入 PathSandbox 后文件工具受沙箱约束
    public static func makeAll(sandbox: PathSandbox?) -> [any Tool] {
        [ReadFileTool(sandbox: sandbox), WriteFileTool(sandbox: sandbox), ListFilesTool(sandbox: sandbox),
         ExecCommandTool(), WebFetchTool()]
    }

    /// 根据工具名推断分类（UI 展示用）
    public static func category(for name: String) -> (id: String, display: String) {
        if name.hasPrefix("mcp_") {
            return ("mcp", "MCP")
        }
        switch name {
        case "read_file", "write_file", "list_files": return ("filesystem", "文件")
        case "exec_command": return ("terminal", "终端")
        case "web_fetch": return ("network", "网络")
        case "use_skill", "list_skills": return ("skills", "技能")
        default: return ("general", "通用")
        }
    }
}
