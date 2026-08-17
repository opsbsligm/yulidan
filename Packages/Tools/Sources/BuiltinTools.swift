import Foundation
import LLM
import ServiceContainer

// 内置真实工具集 — 供 ToolRegistry 注册后在 UI 中真实执行
// ⚠️ 安全提示：exec_command / write_file 具备真实执行能力，生产环境接入前
//    建议叠加沙箱（Packages/Sandbox）与权限确认。

// MARK: - read_file

public struct ReadFileTool: Tool {
    public let name = "read_file"
    public let description = "读取文件内容（默认限制 200KB）"
    public let parameterSchema = "{\"path\": \"文件绝对路径\"}"

    public func execute(_ args: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        guard let path = args["path"]?.trimmingCharacters(in: .whitespaces), !path.isEmpty else {
            return ToolResult(content: [.text("错误：缺少参数 path")],
                              error: ToolError(name: "read_file", code: "missing_arg", message: "缺少 path 参数"))
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
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
    public let name = "write_file"
    public let description = "写入文件内容（目录不存在时自动创建）"
    public let parameterSchema = "{\"path\": \"文件绝对路径\", \"content\": \"要写入的内容\"}"

    public func execute(_ args: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        guard let path = args["path"]?.trimmingCharacters(in: .whitespaces), !path.isEmpty else {
            return ToolResult(content: [.text("错误：缺少参数 path")],
                              error: ToolError(name: "write_file", code: "missing_arg", message: "缺少 path 参数"))
        }
        let content = args["content"] ?? ""
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
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
    public let name = "list_files"
    public let description = "列出目录下的文件与子目录"
    public let parameterSchema = "{\"path\": \"目录绝对路径，默认当前目录\", \"limit\": \"最多显示条数，默认 100\"}"

    public func execute(_ args: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        let rawPath = (args["path"] ?? ".").trimmingCharacters(in: .whitespaces)
        let url = URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath)
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
    public let name = "exec_command"
    public let description = "在系统 shell 中执行命令并返回输出（⚠️ 具备真实执行能力，请谨慎）"
    public let parameterSchema = "{\"cmd\": \"要执行的 shell 命令\", \"timeout\": \"超时秒数，默认 30\"}"

    public func execute(_ args: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        guard let cmd = args["cmd"]?.trimmingCharacters(in: .whitespaces), !cmd.isEmpty else {
            return ToolResult(content: [.text("错误：缺少参数 cmd")],
                              error: ToolError(name: "exec_command", code: "missing_arg", message: "缺少 cmd 参数"))
        }
        let timeout = Double(args["timeout"] ?? "30") ?? 30
        do {
            let out = try await Self.run(cmd: cmd, timeout: timeout)
            return ToolResult(content: [.text(out)],
                              meta: ["cmd": String(cmd.prefix(200))])
        } catch {
            return ToolResult(content: [.text("❌ 命令执行失败：\(error.localizedDescription)")],
                              error: ToolError(name: "exec_command", code: "exec_failed", message: error.localizedDescription))
        }
    }

    /// 执行 shell 命令，合并 stdout/stderr，带超时
    /// 实现说明：全部阻塞操作放在后台队列；stdout/stderr 在两个独立线程
    /// 并行读取（避免管道缓冲区写满导致死锁），超时后 terminate。
    static func run(cmd: String, timeout: TimeInterval) async throws -> String {
        // @unchecked Sendable 盒子：用于把 Process/Pipe 传给 @Sendable 闭包
        final class RunBox: @unchecked Sendable {
            let process: Process
            let outPipe: Pipe
            let errPipe: Pipe
            let group: DispatchGroup
            var outData = Data()
            var errData = Data()
            init(process: Process, outPipe: Pipe, errPipe: Pipe, group: DispatchGroup) {
                self.process = process
                self.outPipe = outPipe
                self.errPipe = errPipe
                self.group = group
            }
        }
        return try await withCheckedThrowingContinuation { cont in
            let process = Process()
            let outPipe = Pipe()
            let errPipe = Pipe()
            let group = DispatchGroup()
            let box = RunBox(process: process, outPipe: outPipe, errPipe: errPipe, group: group)

            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                box.outData = box.outPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                box.errData = box.errPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", cmd]
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
                return
            }

            // 等待退出（带超时）
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning {
                if Date() > deadline {
                    process.terminate()
                    break
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            process.waitUntilExit()
            group.wait()

            let combined = Self.combineOutput(stdout: box.outData, stderr: box.errData)
            cont.resume(returning: "✅ 退出码 \(process.terminationStatus)\n\n\(combined)")
        }
    }

    /// 合并 stdout/stderr 为结果文本（无输出时给占位说明；截断至 50000 字符）
    static func combineOutput(stdout: Data, stderr: Data) -> String {
        var result = ""
        if let o = String(data: stdout, encoding: .utf8), !o.isEmpty {
            result += o
        }
        if let e = String(data: stderr, encoding: .utf8), !e.isEmpty {
            result += (result.isEmpty ? "" : "\n") + "[stderr]\n" + e
        }
        if result.isEmpty {
            result = "（无输出）"
        }
        return String(result.prefix(50000))
    }
}

// MARK: - 注册辅助

public enum BuiltinTools {
    /// 创建全部内置工具实例
    public static func makeAll() -> [any Tool] {
        [ReadFileTool(), WriteFileTool(), ListFilesTool(), ExecCommandTool()]
    }

    /// 根据工具名推断分类（UI 展示用）
    public static func category(for name: String) -> (id: String, display: String) {
        switch name {
        case "read_file", "write_file", "list_files": ("filesystem", "文件")
        case "exec_command": ("terminal", "终端")
        default: ("general", "通用")
        }
    }
}
