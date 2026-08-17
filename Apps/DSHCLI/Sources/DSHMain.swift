import Agent
import ArgumentParser
import Foundation
import HarnessCore
import LLM
import ServiceContainer
import Session
import Tools

@main
struct DSH: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dsh",
        abstract: "Swift Harness — macOS Native AI Agent Framework",
        version: "0.1.0",
        subcommands: [WebCommand.self, HeadlessCommand.self, PluginCommand.self]
    )
}

// MARK: - 配置（环境变量驱动，敏感信息不落盘）

/// CLI 运行配置：全部来自环境变量，无 Keychain/UserDefaults 依赖
enum DSHConfig {
    /// 提供商 → 默认 base URL（与 GUI 的 ModelProvider.baseURL 保持一致）
    static func baseURL(for provider: String) -> URL? {
        switch provider {
        case "openai": URL(string: "https://api.openai.com/v1")
        case "deepseek": URL(string: "https://api.deepseek.com/v1")
        case "anthropic": URL(string: "https://api.anthropic.com/v1")
        case "local": URL(string: "http://localhost:11434/v1")
        default: nil
        }
    }

    /// 提供商 → 默认模型
    static func defaultModel(for provider: String) -> String {
        switch provider {
        case "openai": "gpt-4o-mini"
        case "anthropic": "claude-sonnet-4-20250514"
        case "local": "llama3.1"
        default: "deepseek-chat"
        }
    }

    struct Resolved: Sendable {
        let provider: String
        let apiKey: String
        let baseURL: URL
        let model: String
        let maxSteps: Int
        let systemPrompt: String?
    }

    static func resolve() throws -> Resolved {
        let provider = (ProcessInfo.processInfo.environment["HARNESS_PROVIDER"] ?? "deepseek").lowercased()
        let baseURL = ProcessInfo.processInfo.environment["HARNESS_BASE_URL"]
            .flatMap { URL(string: $0) }
            ?? baseURL(for: provider)
        guard let baseURL else {
            throw CLIError.configMissing("HARNESS_PROVIDER（openai/deepseek/anthropic/local）或 HARNESS_BASE_URL")
        }
        let apiKey = ProcessInfo.processInfo.environment["HARNESS_API_KEY"] ?? ""
        if provider != "local", apiKey.isEmpty {
            throw CLIError.configMissing("HARNESS_API_KEY（\(provider) 需要 API Key）")
        }
        let model = ProcessInfo.processInfo.environment["HARNESS_MODEL"] ?? defaultModel(for: provider)
        let maxSteps = Int(ProcessInfo.processInfo.environment["HARNESS_MAX_STEPS"] ?? "") ?? 8
        let systemPrompt = ProcessInfo.processInfo.environment["HARNESS_SYSTEM_PROMPT"]
        return Resolved(provider: provider, apiKey: apiKey, baseURL: baseURL, model: model, maxSteps: maxSteps, systemPrompt: systemPrompt)
    }
}

/// 与 GUI AppViewModel.makeProvider 一致的适配器工厂
enum ProviderFactory {
    static func make(_ cfg: DSHConfig.Resolved) -> any LLMProvider {
        switch cfg.provider {
        case "openai":
            OpenAIAdapter(apiKey: cfg.apiKey, baseURL: cfg.baseURL)
        case "anthropic":
            AnthropicAdapter(apiKey: cfg.apiKey, baseURL: cfg.baseURL)
        case "local":
            LocalAdapter(apiKey: cfg.apiKey.isEmpty ? "local" : cfg.apiKey, baseURL: cfg.baseURL)
        default:
            DeepSeekAdapter(apiKey: cfg.apiKey, baseURL: cfg.baseURL)
        }
    }
}

enum CLIError: Error, CustomStringConvertible {
    case configMissing(String)
    case manifestInvalid(String)

    var description: String {
        switch self {
        case let .configMissing(k): "缺少配置：\(k)"
        case let .manifestInvalid(r): "插件清单无效：\(r)"
        }
    }
}

// MARK: - run（Headless Agent）

struct HeadlessCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a headless agent session",
        discussion: """
        环境变量：
          HARNESS_API_KEY     API Key（local 提供商可省略）
          HARNESS_PROVIDER    openai | deepseek | anthropic | local（默认 deepseek）
          HARNESS_BASE_URL    覆盖默认 base URL
          HARNESS_MODEL       模型名（默认按提供商选择）
          HARNESS_MAX_STEPS   单轮最大工具调用步数（默认 8）
          HARNESS_SYSTEM_PROMPT 系统提示词（可选）
        """
    )

    @Argument(help: "The prompt to execute")
    var prompt: String

    @Flag(name: .shortAndLong, help: "Show tool call details")
    var verbose: Bool = false

    func run() async throws {
        let cfg = try DSHConfig.resolve()
        FileHandle.standardError.write(Data("[dsh] \(cfg.baseURL.absoluteString) / \(cfg.model)\n".utf8))

        let llm = ProviderFactory.make(cfg)
        let tools = ToolRegistry()
        for tool in BuiltinTools.makeAll() {
            await tools.register(tool)
        }
        let loop = AgentLoop(
            id: AgentID(), sessionID: SessionID(), llm: llm, tools: tools,
            model: cfg.model, systemPrompt: cfg.systemPrompt, maxSteps: cfg.maxSteps
        )

        let startTurns = await loop.turnNumber
        await loop.send(UserMessage(content: [.text(prompt)]), target: .nextTurn, wakeup: true)

        // 轮询等待 turn 完成（真实 LLM 调用耗时较长，给 10 分钟上限）
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline {
            if await loop.turnNumber > startTurns, await loop.currentStatus != .running {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        let result = await loop.lastTurnResult
        let toolResults = await loop.allToolResults

        if verbose, !toolResults.isEmpty {
            printToolDetails(toolResults)
        }

        if let error = result.error {
            throw CLIError.manifestInvalid("Agent 执行失败：\(error)")
        }
        // 输出助手最终回答的纯文本
        for message in result.messages {
            for block in message.content {
                if case let .text(t) = block {
                    print(t)
                }
            }
        }
        if result.messages.isEmpty {
            print("（Agent 未产生文本回复）")
        }
    }
}

/// 输出工具调用明细到 stderr（-v 时）
private func printToolDetails(_ toolResults: [ToolResult]) {
    FileHandle.standardError.write(Data("[dsh] 工具调用 \(toolResults.count) 次\n".utf8))
    for (i, tr) in toolResults.enumerated() {
        let err = tr.error.map { "（错误：\($0.message)）" } ?? ""
        var preview = "…"
        if let first = tr.content.first, case let .text(t) = first {
            preview = String(t.prefix(120))
        }
        FileHandle.standardError.write(Data("[dsh] \(i + 1). \(preview)\(err)\n".utf8))
    }
}

// MARK: - web（Phase 3 路线图，未实现）

struct WebCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "web",
        abstract: "Start the web UI（未实现：Phase 3 路线图，当前请直接使用 GUI 应用 HarnessApp）"
    )

    @Flag(name: .shortAndLong, help: "Run in headless mode")
    var headless: Bool = false

    @Option(name: .shortAndLong, help: "Port to listen on")
    var port: Int = 3080

    func run() async throws {
        print("Web UI 尚未实现（Phase 3 路线图：本地 HTTP 服务器 + 浏览器会话界面）。")
        print("当前请使用 GUI 应用：HarnessApp（.build/arm64-apple-macosx/debug/HarnessApp.app）。")
    }
}

// MARK: - plugin（清单校验 + 安装记录，动态代码加载见 Phase 3）

struct PluginCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plugin",
        abstract: "Manage plugins",
        subcommands: [InstallCommand.self, ListCommand.self]
    )
}

/// 安装记录（~/.harness/installed-plugins.json）
struct InstalledPluginRecord: Codable, Sendable {
    struct Manifest: Codable, Sendable {
        let id: String
        let name: String
        let version: String
        let description: String?
    }

    let manifest: Manifest
    let source: String
    let installedAt: Date
}

enum PluginStore {
    static var storeURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".harness", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("installed-plugins.json")
    }

    static func load() -> [InstalledPluginRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601 // 与 save 的编码策略保持一致
        guard let data = try? Data(contentsOf: storeURL),
              let records = try? decoder.decode([InstalledPluginRecord].self, from: data)
        else { return [] }
        return records
    }

    static func save(_ records: [InstalledPluginRecord]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: storeURL, options: .atomic)
    }

    /// 校验清单 JSON（id/name/version 必填）
    static func validateManifest(_ data: Data, source: String) throws -> InstalledPluginRecord.Manifest {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CLIError.manifestInvalid("不是合法 JSON 对象（来源：\(source)）")
        }
        var manifest: [String: String] = [:]
        for key in ["id", "name", "version"] {
            guard let v = obj[key] as? String, !v.isEmpty else {
                throw CLIError.manifestInvalid("缺少必填字段 \"\(key)\"（来源：\(source)）")
            }
            manifest[key] = v
        }
        let description = obj["description"] as? String
        return InstalledPluginRecord.Manifest(
            id: manifest["id"]!, name: manifest["name"]!, version: manifest["version"]!,
            description: description
        )
    }
}

struct InstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install a plugin (manifest validation + install record; dynamic loading is Phase 3)",
        discussion: "参数为本地路径（JSON 文件，或包含 plugin.json 的目录）或 https URL。"
    )

    @Argument(help: "Plugin manifest path or URL")
    var plugin: String

    func run() async throws {
        let source = plugin
        let data: Data
        if let url = URL(string: plugin), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            print("下载插件清单：\(url.absoluteString)")
            let (d, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                throw CLIError.manifestInvalid("下载失败（来源：\(source)）")
            }
            data = d
        } else {
            let fm = FileManager.default
            var isDir: ObjCBool = false
            let localURL = URL(fileURLWithPath: (plugin as NSString).expandingTildeInPath)
            guard fm.fileExists(atPath: localURL.path, isDirectory: &isDir) else {
                throw CLIError.manifestInvalid("路径不存在：\(source)")
            }
            let manifestURL = isDir.boolValue
                ? localURL.appendingPathComponent("plugin.json")
                : localURL
            guard let d = try? Data(contentsOf: manifestURL) else {
                throw CLIError.manifestInvalid("无法读取 \(manifestURL.lastPathComponent)")
            }
            data = d
        }

        let manifest = try PluginStore.validateManifest(data, source: source)
        var records = PluginStore.load()
        // 同 id 覆盖（升级语义）
        records.removeAll { $0.manifest.id == manifest.id }
        let record = InstalledPluginRecord(manifest: manifest, source: source, installedAt: Date())
        records.append(record)
        try PluginStore.save(records)

        print("✅ 插件清单校验通过并已记录：\(manifest.name) v\(manifest.version)（id: \(manifest.id)）")
        print("⚠️ 动态代码加载尚未实现（Phase 3 路线图）；当前记录仅作安装台账使用。")
    }
}

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List installed plugins"
    )

    func run() async throws {
        // 内置插件（随 HarnessCore 分发，启动时自动注册）
        print("内置插件：")
        let builtIns: [(id: String, name: String, desc: String)] = [
            ("file-system", "文件系统", BuiltInPluginCatalog.info["file-system"]?.description ?? ""),
            ("terminal", "终端", BuiltInPluginCatalog.info["terminal"]?.description ?? ""),
        ]
        for p in builtIns {
            print("  • \(p.name)（\(p.id)）— \(p.desc)")
        }

        let records = PluginStore.load()
        if records.isEmpty {
            print("已安装插件：（无）")
        } else {
            print("已安装插件：")
            for r in records {
                print("  • \(r.manifest.name) v\(r.manifest.version)（\(r.manifest.id)）— 来源：\(r.source)")
            }
        }
    }
}
