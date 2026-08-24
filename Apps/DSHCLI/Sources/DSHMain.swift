import Agent
import ArgumentParser
import Foundation
import HarnessCore
import LLM
import MCP
import Memory
import Prompt
import RAG
import ServiceContainer
import Session
import Skill
import Subagent
import Tools
import WebUI

@main
struct DSH: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dsh",
        abstract: "Swift Harness — macOS Native AI Agent Framework",
        version: "0.1.0",
        subcommands: [WebCommand.self, HeadlessCommand.self, PluginCommand.self, AgentsCommand.self,
                      SkillsCommand.self, MCPCommand.self]
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
        // MCP 服务发现：连接 ~/.harness/mcp/servers.json 声明的 stdio 服务器，工具自动注册
        await connectMCPServers(to: tools)
        // RAG 知识库：注册 search_knowledge / add_knowledge / list_knowledge 工具
        await Self.registerRAGTools(to: tools)
        // 技能系统：注册 list/use/save/debug 技能工具（内置 + ~/.harness/skills）
        let skillRuntime = await Self.makeSkillRuntime(to: tools)
        // 提示词工程层：用户未显式配置系统提示词时，渲染内置 agent 角色模板（模型差异化自动适配）
        // 记忆系统：相关长期记忆注入 {{#context}} 条件块
        let promptContext = await Self.memoryPromptContext(query: prompt)
        let promptEngine = await SharedPromptEngine.instance.get()
        var systemPrompt = cfg.systemPrompt
        if systemPrompt == nil {
            systemPrompt = try? await promptEngine.renderSystemPrompt(template: PromptEngine.agentTemplate,
                                                                      model: cfg.model, context: promptContext)
        }
        // P2 日期注入（与 App 路径一致）：用户自定义/渲染模板两路统一注入当前日期+星期
        systemPrompt = systemPrompt.map { CurrentDateContext.inject(into: $0) }
        let loop = AgentLoop(
            id: AgentID(), sessionID: SessionID(), llm: llm, tools: tools,
            model: cfg.model, systemPrompt: systemPrompt, maxSteps: cfg.maxSteps
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
        // 记忆反馈闭环：蒸馏本轮交换（显式记住/纠正/决策/事实）→ 长期记忆，并落盘
        await Self.processMemoryFeedback(prompt: prompt, result: result)
        // 技能进化（Hermes 范式）：观测本轮任务工具序列，相似重复任务达阈值自动沉淀为可复用技能
        await Self.observeSkillEvolution(task: prompt, result: result, registry: skillRuntime.registry)
    } // MCP 服务发现：逐个连接 stdio 服务器，工具自动注册进给定注册表（失败仅提示，不中断）
    private func connectMCPServers(to tools: ToolRegistry) async {
        let configs = MCPDiscovery.loadConfigs()
        guard !configs.isEmpty else {
            return
        }
        let manager = MCPServerManager()
        for config in configs {
            let descriptor = await manager.connectStdio(config, into: tools)
            if descriptor.isAvailable {
                FileHandle.standardError.write(Data("[dsh] MCP 已连接：\(config.name)（\(descriptor.toolCount ?? 0) 个工具）\n".utf8))
            } else {
                FileHandle.standardError.write(Data("[dsh] MCP 连接失败：\(config.name)\n".utf8))
            }
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

// MARK: - agents（多 Agent 协作：并行子任务）

struct AgentsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agents",
        abstract: "Multi-Agent collaboration (parallel subagents)",
        subcommands: [AgentsRunCommand.self]
    )
}

struct AgentsRunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Spawn one subagent per task and wait for all to finish",
        discussion: """
        每个任务一个独立 AgentLoop（共享工具注册表），最多 --parallel 个并行。
        生命周期事件输出到 stderr，最终结果输出到 stdout；任一失败退出码为 1。
        环境变量同 run 命令（HARNESS_API_KEY / HARNESS_PROVIDER / ...）。
        """
    )

    @Argument(help: "Task descriptions (one subagent per task)")
    var tasks: [String] = []

    @Option(name: .shortAndLong, help: "Max parallel subagents")
    var parallel: Int = 4

    @Option(help: "Per-task timeout in seconds")
    var timeout: Double = 300

    func run() async throws {
        guard !tasks.isEmpty else {
            throw CLIError.configMissing("至少一个任务参数")
        }
        let cfg = try DSHConfig.resolve()
        let llm = ProviderFactory.make(cfg)
        let tools = ToolRegistry()
        for tool in BuiltinTools.makeAll() {
            await tools.register(tool)
        }
        let promptEngine = await SharedPromptEngine.instance.get()
        var systemPrompt = cfg.systemPrompt
        if systemPrompt == nil {
            systemPrompt = try? await promptEngine.renderSystemPrompt(template: PromptEngine.subagentTemplate, model: cfg.model)
        }
        // P2 日期注入（与 App 路径一致）：用户自定义/渲染模板两路统一注入当前日期+星期
        systemPrompt = systemPrompt.map { CurrentDateContext.inject(into: $0) }
        let coordinator = SubagentCoordinator(maxConcurrent: max(1, parallel), onEvent: Self.logEvent)
        for (index, task) in tasks.enumerated() {
            let agent = AgentLoop(
                sessionID: SessionID(), llm: llm, tools: tools,
                model: cfg.model, systemPrompt: systemPrompt, maxSteps: cfg.maxSteps
            )
            let name = "task\(index + 1): \(String(task.prefix(16)))"
            _ = await coordinator.spawn(agent: agent, spec: .init(name: name, task: task, timeout: timeout))
        }
        let states = await coordinator.waitForAll()
        if Self.printResults(states) {
            throw ExitCode(1)
        }
    }

    /// 生命周期事件 → stderr
    private static func logEvent(_ event: SubagentEvent) {
        switch event {
        case let .spawned(id, name):
            FileHandle.standardError.write(Data("[agents] 排队：\(name)（\(id.rawValue.uuidString.prefix(8))）\n".utf8))
        case let .started(id):
            FileHandle.standardError.write(Data("[agents] 启动：\(id.rawValue.uuidString.prefix(8))\n".utf8))
        case let .finished(_, state):
            FileHandle.standardError.write(Data("[agents] 结束：\(state.name) → \(state.phase.rawValue)（\(String(format: "%.1f", state.elapsed ?? 0))s）\n".utf8))
        case let .reclaimed(id):
            FileHandle.standardError.write(Data("[agents] 回收：\(id.rawValue.uuidString.prefix(8))\n".utf8))
        }
    }

    /// 打印全部结果到 stdout；返回是否存在失败
    private static func printResults(_ states: [SubagentState]) -> Bool {
        var failed = false
        for state in states {
            print("=== \(state.name) → \(state.phase.rawValue)（\(String(format: "%.1f", state.elapsed ?? 0))s）")
            if let error = state.error {
                print("错误：\(error)")
                failed = true
            }
            if let first = state.result?.messages.first {
                for block in first.content {
                    if case let .text(t) = block {
                        print(t)
                    }
                }
            }
        }
        return failed
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

// MARK: - skills（技能系统：内置 + ~/.harness/skills）

struct SkillsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skills",
        abstract: "Manage skills (built-in + ~/.harness/skills)",
        subcommands: [SkillsListCommand.self, SkillsShowCommand.self, SkillsExportCommand.self,
                      SkillsImportCommand.self, SkillsDebugCommand.self, SkillsVersionsCommand.self,
                      SkillsRestoreCommand.self, SkillsDeleteCommand.self]
    )
}

struct SkillsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all skills"
    )

    func run() async throws {
        let all = SkillsCLI.allSkills()
        guard !all.isEmpty else {
            print("（无可用技能）")
            return
        }
        print("\(all.count) 个技能：")
        for skill in all {
            print("  • \(skill.summary)（来源：\(skill.source)）")
        }
        print("\n用法：dsh skills show <名称> 查看完整指令")
    }
}

struct SkillsShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show a skill's full instructions"
    )

    @Argument(help: "Skill name")
    var name: String

    func run() async throws {
        guard let skill = SkillsCLI.allSkills().first(where: { $0.name == name }) else {
            print("技能不存在：\(name)（可用：dsh skills list）")
            throw ExitCode(1)
        }
        print("【\(skill.name)】\(skill.description)（来源：\(skill.source)）\n")
        print(skill.instructions)
    }
}

// MARK: - skills 公共逻辑 + 导入导出

enum SkillsCLI {
    /// 内置 + 用户目录技能（同名时用户覆盖内置），按名称排序
    static func allSkills() -> [Skill] {
        var byName: [String: Skill] = [:]
        for skill in BuiltInSkills.makeAll() + SkillStore.load(from: SkillStore.userSkillsDirectory) {
            byName[skill.name] = skill
        }
        return byName.values.sorted { $0.name < $1.name }
    }
}

struct SkillsExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export a skill to a SKILL.md file"
    )

    @Argument(help: "Skill name")
    var name: String

    @Option(name: .shortAndLong, help: "Output path (default ./<name>.skill.md)")
    var out: String?

    func run() async throws {
        guard let skill = SkillsCLI.allSkills().first(where: { $0.name == name }) else {
            print("技能不存在：\(name)（可用：dsh skills list）")
            throw ExitCode(1)
        }
        let target = URL(fileURLWithPath: ((out ?? "./\(name).skill.md") as NSString).expandingTildeInPath)
        do {
            try SkillStore.serialize(skill).write(to: target, atomically: true, encoding: .utf8)
        } catch {
            print("写入失败：\(target.path)（\(error.localizedDescription)）")
            throw ExitCode(1)
        }
        print("✅ 已导出 \(skill.name)（来源：\(skill.source)）→ \(target.path)")
    }
}

struct SkillsImportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import a SKILL.md file (or skill directory) into ~/.harness/skills"
    )

    @Argument(help: "SKILL.md path or skill directory")
    var path: String

    func run() async throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let sourceURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDir) else {
            print("路径不存在：\(path)")
            throw ExitCode(1)
        }
        let fileURL = isDir.boolValue ? sourceURL.appendingPathComponent("SKILL.md") : sourceURL
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            print("无法读取 \(fileURL.lastPathComponent)")
            throw ExitCode(1)
        }
        guard let skill = SkillStore.parse(text, source: fileURL.path) else {
            print("❌ 不是合法的技能文件（需要 --- frontmatter --- 且含 name 字段）：\(fileURL.path)")
            throw ExitCode(1)
        }
        let target = SkillStore.userSkillsDirectory.appendingPathComponent(skill.name, isDirectory: true)
            .appendingPathComponent("SKILL.md")
        let existed = fm.fileExists(atPath: target.path)
        do {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: target, atomically: true, encoding: .utf8)
        } catch {
            print("写入失败：\(target.path)（\(error.localizedDescription)）")
            throw ExitCode(1)
        }
        print("✅ 已导入 \(skill.name)（\(existed ? "覆盖" : "新增")）→ \(target.path)")
    }
}
