import Agent
import AppKit
import Foundation
import HarnessCore
import LLM
import Memory
import Notifications
import PluginXPC
import Prompt
import RAG
import Sandbox

// 技术债：本文件/类超过长度阈值，计划拆分为 会话管理 / 生成流程 / 设置 三个 ViewModel（见 docs/CODE_REVIEW.md）
// swiftlint:disable file_length type_body_length
import MCP
import ServiceContainer
import Session
import Skill
import Subagent
import SwiftUI
import Terminal
import Tools

// MARK: - 模型提供商

enum ModelProvider: String, CaseIterable, Identifiable {
    case openAI = "openai"
    case deepSeek = "deepseek"
    case anthropic
    case local

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .deepSeek: "DeepSeek"
        case .anthropic: "Anthropic"
        case .local: "本地模型"
        }
    }

    var icon: String {
        switch self {
        case .openAI: "sparkle"
        case .deepSeek: "brain"
        case .anthropic: "cpu"
        case .local: "server.rack"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: "gpt-4o"
        case .deepSeek: "deepseek-chat"
        case .anthropic: "claude-sonnet-4-20250514"
        case .local: "local"
        }
    }
}

// MARK: - 文件附件

struct FileAttachment: Identifiable, Equatable {
    let id: UUID
    let name: String
    let path: String
    let content: String
    let truncated: Bool

    init(id: UUID = UUID(), name: String, path: String, content: String, truncated: Bool) {
        self.id = id; self.name = name; self.path = path
        self.content = content; self.truncated = truncated
    }
}

// MARK: - 插件显示模型

struct PluginDisplayItem: Identifiable, Hashable {
    let id: String
    let name: String
    let version: String
    let state: PluginState
    let isActive: Bool
    let permissions: [String]
    let author: String?
    let description: String

    init(id: String, name: String, version: String, state: PluginState,
         isActive: Bool, permissions: [String], author: String?, description: String) {
        self.id = id; self.name = name; self.version = version; self.state = state
        self.isActive = isActive; self.permissions = permissions
        self.author = author; self.description = description
    }

    /// 从 PluginManager 的真实 PluginInfo 构造
    init(info: PluginInfo) {
        id = info.id.rawValue
        name = info.name
        version = info.version
        state = info.state
        isActive = info.state == .active
        permissions = BuiltInPluginCatalog.info[info.id.rawValue]?.permissions ?? []
        author = "Harness 内置"
        description = BuiltInPluginCatalog.info[info.id.rawValue]?.description ?? "内置插件"
    }
}

/// 权限的中文展示名（市场条目用；内置插件另有 BuiltInPluginCatalog）
extension Permission {
    var display: String {
        switch self {
        case .filesystemRead: "文件读取"
        case .filesystemWrite: "文件写入"
        case .shellExecution: "Shell 执行"
        case .networkAccess: "网络访问"
        case .subprocessSpawn: "子进程创建"
        case .terminalAccess: "终端访问"
        case .clipboardAccess: "剪贴板"
        case .screenCapture: "屏幕捕获"
        case .keychainAccess: "钥匙串"
        }
    }
}

// MARK: - 市场条目显示模型

struct MarketplaceDisplayItem: Identifiable, Hashable {
    let id: String
    let name: String
    let version: String
    let description: String
    let author: String?
    let permissions: [String]
    let isInstalled: Bool
    let hasUpdate: Bool
    let incompatibleReason: String?

    init(entry: MarketplaceEntry) {
        id = entry.listing.id.rawValue
        name = entry.listing.name
        version = entry.listing.version.description
        description = entry.listing.description
        author = entry.listing.author
        permissions = entry.listing.permissions.map(\.display)
        isInstalled = entry.isInstalled
        hasUpdate = entry.hasUpdate
        switch entry.status {
        case let .incompatible(reason): incompatibleReason = reason
        case .notInstalled, .installed: incompatibleReason = nil
        }
    }
}

// MARK: - 子任务显示模型

struct SubagentDisplayItem: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let phase: SubagentPhase
    let resultText: String?
    let error: String?
    let elapsed: TimeInterval?
    let stepLines: [String]
    let finishedAt: Date?

    init(state: SubagentState) {
        id = state.id.rawValue.uuidString
        name = state.name
        phase = state.phase
        var text: String?
        if let firstMessage = state.result?.messages.first {
            let joined = firstMessage.content.compactMap { block -> String? in
                if case let .text(s) = block {
                    return s
                }
                return nil
            }.joined()
            text = joined.isEmpty ? nil : joined
        }
        resultText = text
        error = state.error
        elapsed = state.elapsed
        stepLines = Self.stepLines(from: state.result?.steps ?? [])
        finishedAt = state.finishedAt
    }

    /// 从持久化历史构造
    init(from history: SubagentHistoryItem) {
        id = history.id
        name = history.name
        phase = history.phase
        resultText = history.resultText
        error = history.error
        elapsed = history.elapsed
        stepLines = history.stepLines
        finishedAt = history.finishedAt
    }

    /// 转为持久化历史条目
    var toHistory: SubagentHistoryItem {
        SubagentHistoryItem(id: id, name: name, phase: phase, resultText: resultText,
                            error: error, elapsed: elapsed, stepLines: stepLines,
                            finishedAt: finishedAt ?? Date())
    }

    /// 执行过程时间线（工具调用 / 文本回复，按步序）
    static func stepLines(from steps: [AssistantMessage]) -> [String] {
        steps.enumerated().map { index, msg in
            let n = index + 1
            let calls = msg.content.compactMap { block -> String? in
                if case let .toolCall(c) = block {
                    return "\(c.name) \(c.arguments)"
                }
                return nil
            }
            if !calls.isEmpty {
                return "步骤\(n) · 工具调用 \(calls.map { String($0.prefix(60)) }.joined(separator: "；"))"
            }
            let text = msg.content.compactMap { block -> String? in
                if case let .text(s) = block {
                    return s
                }
                return nil
            }.joined()
            return "步骤\(n) · 回复 \(text.isEmpty ? "（无文本）" : String(text.prefix(80)))"
        }
    }
}

// MARK: - 工具显示模型

struct ToolDisplayItem: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let parameters: String
    let category: String
    let categoryDisplay: String
    let isExecuted: Bool
    let lastResult: String?
    let executing: Bool

    init(id: String, name: String, description: String, parameters: String,
         category: String, categoryDisplay: String = "", isExecuted: Bool = false,
         lastResult: String? = nil, executing: Bool = false) {
        self.id = id; self.name = name; self.description = description
        self.parameters = parameters; self.category = category
        self.categoryDisplay = categoryDisplay; self.isExecuted = isExecuted
        self.lastResult = lastResult; self.executing = executing
    }

    init(schema: ToolSchema) {
        let cat = BuiltinTools.category(for: schema.name)
        id = schema.name; name = schema.name
        description = schema.description; parameters = schema.parameters
        category = cat.id; categoryDisplay = cat.display
        isExecuted = false; lastResult = nil; executing = false
    }
}

// MARK: - 主视图模型

@MainActor
final class AppViewModel: ObservableObject {
    // 导航
    @Published var selectedTab: AppTab = .chat
    @Published var selectedSession: SessionRecord?
    @Published var toastMessage: String?

    // 对话
    @Published var sessions: [SessionRecord] = []
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    /// 当前正在执行的工具名（Codex 式实时进度；nil = 无工具运行）
    @Published var activeToolName: String?
    @Published var generationError: String?
    @Published var lastUserMessage = ""
    @Published var attachments: [FileAttachment] = []

    /// 会话搜索结果（nil = 未搜索；非 nil 时侧栏展示该列表）
    @Published var searchResults: [SessionRecord]?
    private var searchTask: Task<Void, Never>?

    /// 模型
    @Published var llmConfig: LLMConfig

    // 插件 / 工具
    @Published var plugins: [PluginDisplayItem] = []
    @Published var marketplaceEntries: [MarketplaceDisplayItem] = []
    @Published var tools: [ToolDisplayItem] = []

    /// 基础设施（真实组件）
    let sessionDB: SessionDB?
    /// 测试钩子：指定会话数据库路径（nil = 默认 ~/Library/Application Support/Harness/sessions.sqlite）
    static var sessionDBURLOverride: URL?
    let pluginManager: PluginManager
    let marketplace: PluginMarketplace
    let notificationCenter: NotificationCoordinator
    let xpcHost: XPCPluginHost
    @Published var isolatedPluginIDs: Set<String> = []
    let toolRegistry: ToolRegistry
    let mcpManager: MCPServerManager
    let subagentCoordinator: SubagentCoordinator
    /// 记忆引擎（registerStartupTools 装配后生效；nil = 未就绪）
    private var memoryEngine: MemoryEngine?
    /// 子任务工具注册表（仅内置工具，不含 spawn_subagent，防递归派生）
    let subagentToolRegistry: ToolRegistry = .init()
    /// 技能注册表（内置 + ~/.harness/skills 用户目录）
    let skillRegistry: SkillRegistry = .init()
    /// 用户技能目录（构造时一次性捕获：长生命周期 VM 期间目录不漂移；
    /// 测试在构造前注入 SkillStore.userSkillsDirectoryOverride 即可隔离）
    let skillUserDirectory: URL
    @Published var skills: [Skill] = []

    /// 多 Agent（默认值 = 磁盘历史，重启后终态子任务仍可见）
    @Published var subagents: [SubagentDisplayItem] = AppViewModel.loadSubagentHistoryItems()

    private var generateTask: Task<Void, Never>?
    /// 当前生成所用的 AgentLoop（stopGenerating 时同步取消；nil = 无进行中生成）
    private var chatAgent: AgentLoop?
    /// 会话级持久 AgentLoop 缓存（跨轮保留完整工具上下文：工具调用/结果 wire 历史）
    private var sessionLoops: [SessionID: AgentLoop] = [:]
    /// LRU 访问序（最旧在前）
    private var sessionLoopOrder: [SessionID] = []
    /// 创建时的上下文指纹（模型服务商/本地地址；变化则重建）
    private var sessionLoopContext: [SessionID: String] = [:]
    /// 缓存上限（超出按 LRU 释放，内存回收防无界增长）
    private static let maxCachedLoops = 8
    /// 测试观测
    static var maxCachedLoopsForTesting: Int {
        maxCachedLoops
    }

    private var sessionTitles: [UUID: String] = [:]
    private nonisolated(unsafe) var configObserver: (any NSObjectProtocol)?

    // MARK: - 初始化

    /// - Parameter skillUserDirectory: 用户技能目录（测试注入隔离目录；生产默认 ~/.harness/skills）
    init(skillUserDirectory: URL? = nil, sessionDBURL: URL? = nil) {
        let container = ServiceContainer()
        let eventBus = EventBus()
        pluginManager = PluginManager(container: container, eventBus: eventBus,
                                      harnessVersion: PluginVersion(major: 0, minor: 1, patch: 0))
        toolRegistry = ToolRegistry()
        mcpManager = MCPServerManager()
        notificationCenter = NotificationCoordinator(
            service: Self.notificationServiceFactory?() ?? SystemNotificationService(),
            isEnabled: UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        )
        xpcHost = XPCPluginHost()
        marketplace = PluginMarketplace(
            manager: pluginManager,
            harnessVersion: PluginVersion(major: 0, minor: 1, patch: 0),
            sources: [LocalBuiltInMarketplaceSource()]
        )
        llmConfig = LLMConfig.load()
        self.skillUserDirectory = skillUserDirectory ?? SkillStore.userSkillsDirectory
        sessionDB = try? SessionDB(dbURL: sessionDBURL ?? Self.sessionDBURLOverride)
        sessionTitles = Self.loadTitles()
        // 先占位（init 两阶段初始化限制），onEvent 由 registerSubagentRuntime 后置赋值
        subagentCoordinator = SubagentCoordinator(maxConcurrent: 4)

        // 启动工具：内置工具（沙箱）+ MCP 演示服务器 + 技能系统
        Task { await self.registerStartupTools() }

        // 安装真实内置插件
        Task {
            do {
                try await self.pluginManager.install(BuiltInFilesystemPlugin())
                try await self.pluginManager.install(BuiltInTerminalPlugin())
            } catch {
                // 安装失败不阻塞启动，列表仍会展示真实状态
            }
            await self.refreshPlugins()
            await self.refreshMarketplace()
            await self.restoreIsolatedPlugins()
            await self.refreshPlugins()
        }

        // 加载持久化会话
        Task { await self.loadSessionsFromDB() }

        // 监听模型配置变更（设置页保存后同步）
        registerConfigObserver()

        // 子任务运行时：生命周期事件回调 + spawn_subagent 工具注册
        registerSubagentRuntime()
    }

    private func registerConfigObserver() {
        configObserver = NotificationCenter.default.addObserver(
            forName: LLMConfig.configDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.llmConfig = LLMConfig.load()
            }
        }
    }

    /// 子任务运行时：协调器生命周期事件跳主线程刷新列表 + 注册 spawn_subagent 工具
    private func registerSubagentRuntime() {
        subagentCoordinator.onEvent = { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshSubagents() }
        }
        Task { [weak self] in await self?.registerSubagentTool() }
    }

    /// 构建并注册 spawn_subagent：子 Agent 用独立子工具注册表（仅内置工具、不含本工具，防递归）
    private func registerSubagentTool() async {
        for tool in BuiltinTools.makeAll(sandbox: Self.makeSandboxFromSettings()) {
            await subagentToolRegistry.register(tool)
        }
        // 提示词工程层：子 Agent 角色模板（模型差异化适配；失败回退原文案）
        let promptEngine = await SharedPromptEngine.instance.get()
        let subagentPrompt = await (try? promptEngine.renderSystemPrompt(
            template: PromptEngine.subagentTemplate, model: llmConfig.modelName
        ))
            ?? "你是子任务执行 Agent：直接完成给定任务，输出简洁，不要反问。"
        let tool = SpawnSubagentTool(
            coordinator: subagentCoordinator,
            subTools: subagentToolRegistry,
            model: llmConfig.modelName,
            systemPrompt: subagentPrompt,
            makeLLM: { [weak self] in
                await MainActor.run {
                    guard let self, self.hasAPIKey else { return nil }
                    let cfg = self.llmConfig
                    let key = KeychainStorage.getAPIKey(forProvider: cfg.providerRaw) ?? ""
                    return self.makeProvider(cfg, key: key)
                }
            }
        )
        await toolRegistry.register(tool)
        await refreshTools()
    }

    /// 启动工具装配：内置工具（按设置注入文件沙箱）+ MCP 演示服务器（内存客户端）+ 技能系统
    private func registerStartupTools() async {
        for tool in BuiltinTools.makeAll(sandbox: Self.makeSandboxFromSettings()) {
            await toolRegistry.register(tool)
        }
        await registerSkillRuntime()
        let demo = MockMCPClient(name: "local")
        await demo.addTool(MCPToolSpec(name: "system_info", description: "获取系统信息（OS 版本 / 架构 / 负载）", inputSchema: "{}")) { _ in
            let runner = TerminalRunner()
            guard let r = try? await runner.run("sw_vers -productVersion; uname -m; uptime", signal: nil) else {
                throw MCPError.serverFailed("系统命令执行失败")
            }
            return r.combinedOutput
        }
        await demo.addTool(MCPToolSpec(name: "current_time", description: "获取当前本地时间", inputSchema: "{}")) { _ in
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
            return fmt.string(from: Date())
        }
        await mcpManager.register(demo, descriptor: MCPServer(name: "local", transport: "in-memory"))
        for tool in await mcpManager.makeTools() {
            await toolRegistry.register(tool)
        }
        // 服务发现：连接 ~/.harness/mcp/servers.json 中声明的 stdio 服务器，工具自动注册进主 Agent 注册表
        // （后台进行，不阻塞启动；连接失败不影响其它服务器）
        let configs = MCPDiscovery.loadConfigs()
        for config in configs {
            Task { [weak self] in
                guard let self else { return }
                _ = await mcpManager.connectStdio(config, into: toolRegistry)
                await refreshTools()
            }
        }
        // RAG 知识库：注册 search_knowledge / add_knowledge / list_knowledge 工具
        // （进程级共享索引 ~/.harness/rag/index.json，与 CLI 同一份库）
        let ragEngine = await SharedRAGEngine.shared.get()
        for tool in KnowledgeTools.makeAll(engine: ragEngine) {
            await toolRegistry.register(tool)
        }
        // 记忆系统：长期记忆 + 反馈闭环（~/.harness/memory/longterm.json；与 RAG 联动）
        let memoryEngine = await SharedMemoryEngine.shared.get()
        await memoryEngine.attachRAG(ragEngine)
        for tool in MemoryTools.makeAll(engine: memoryEngine) {
            await toolRegistry.register(tool)
        }
        self.memoryEngine = memoryEngine
        await refreshTools()
    }

    /// 技能系统：加载内置技能 + 用户目录技能，注册 list_skills / use_skill 工具
    private func registerSkillRuntime() async {
        for skill in BuiltInSkills.makeAll() {
            await skillRegistry.register(skill)
        }
        for skill in SkillStore.load(from: skillUserDirectory) {
            await skillRegistry.register(skill)
        }
        await toolRegistry.register(ListSkillsTool(registry: skillRegistry))
        await toolRegistry.register(UseSkillTool(registry: skillRegistry))
        await toolRegistry.register(SaveSkillTool(registry: skillRegistry))
        await toolRegistry.register(DebugSkillTool(registry: skillRegistry))
        await refreshSkills()
    }

    func refreshSkills() async {
        skills = await skillRegistry.all()
    }

    /// 保存用户技能到 ~/.harness/skills/<slug>/SKILL.md 并注册
    func saveUserSkill(name: String, description: String, tags: String, instructions: String) {
        let slug = Self.skillSlug(name)
        guard !slug.isEmpty else {
            showToast("技能名称需包含字母、数字、中文或中划线")
            return
        }
        guard let file = writeSkillFile(slug: slug,
                                        desc: description.trimmingCharacters(in: .whitespacesAndNewlines),
                                        tags: tagList(from: tags),
                                        body: instructions.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }
        let skill = Skill(name: slug,
                          description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                          instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines),
                          tags: tagList(from: tags), source: file.path)
        Task {
            await skillRegistry.register(skill)
            await self.refreshSkills()
            self.showToast("技能已保存：\(slug)")
        }
    }

    /// 编辑用户技能（名称不可改，重写 SKILL.md 并重新注册；内置技能不可编辑）
    func editUserSkill(_ skill: Skill, description: String, tags: String, instructions: String) {
        guard skill.source != "builtin" else {
            showToast("内置技能不可编辑")
            return
        }
        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            showToast("技能正文不能为空")
            return
        }
        let file = URL(fileURLWithPath: skill.source)
        let dir = file.deletingLastPathComponent()
        guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else {
            showToast("技能目录不存在")
            return
        }
        let text = "---\nname: \(skill.name)\ndescription: \(desc)\ntags: \(tagList(from: tags).joined(separator: ", "))\n---\n\(body)\n"
        guard (try? text.write(to: file, atomically: true, encoding: .utf8)) != nil else {
            showToast("SKILL.md 写入失败")
            return
        }
        let updated = Skill(name: skill.name, description: desc, instructions: body, tags: tagList(from: tags), source: file.path)
        Task {
            await skillRegistry.register(updated)
            await self.refreshSkills()
            self.showToast("技能已更新：\(skill.name)")
        }
    }

    /// 写 SKILL.md（frontmatter + 正文）；失败走 toast 并返回 nil
    private func writeSkillFile(slug: String, desc: String, tags: [String], body: String) -> URL? {
        guard !body.isEmpty else {
            showToast("技能正文不能为空")
            return nil
        }
        let dir = skillUserDirectory.appendingPathComponent(slug, isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else {
            showToast("技能目录创建失败")
            return nil
        }
        let file = dir.appendingPathComponent("SKILL.md")
        let text = "---\nname: \(slug)\ndescription: \(desc)\ntags: \(tags.joined(separator: ", "))\n---\n\(body)\n"
        guard (try? text.write(to: file, atomically: true, encoding: .utf8)) != nil else {
            showToast("SKILL.md 写入失败")
            return nil
        }
        return file
    }

    private func tagList(from raw: String) -> [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// 导入技能文件（SKILL.md 或技能目录）→ 复制到用户目录并注册
    func importSkillFile(at url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            showToast("文件不存在")
            return
        }
        let fileURL = isDir.boolValue ? url.appendingPathComponent("SKILL.md") : url
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            showToast("无法读取 \(fileURL.lastPathComponent)")
            return
        }
        guard let skill = SkillStore.parse(text, source: fileURL.path) else {
            showToast("不是合法技能文件（需含 name 的 frontmatter）")
            return
        }
        let target = skillUserDirectory.appendingPathComponent(skill.name, isDirectory: true)
            .appendingPathComponent("SKILL.md")
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: target, atomically: true, encoding: .utf8)
        } catch {
            showToast("SKILL.md 写入失败")
            return
        }
        let imported = Skill(name: skill.name, description: skill.description, instructions: skill.instructions,
                             tags: skill.tags, source: target.path)
        Task {
            await skillRegistry.register(imported)
            await self.refreshSkills()
            self.showToast("已导入技能：\(skill.name)")
        }
    }

    /// 导出技能：系统保存对话框 → SKILL.md
    func exportSkill(_ skill: Skill) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(skill.name).skill.md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            try SkillStore.serialize(skill).write(to: url, atomically: true, encoding: .utf8)
            showToast("已导出到 \(url.lastPathComponent)")
        } catch {
            showToast("导出失败：\(error.localizedDescription)")
        }
    }

    /// 删除用户技能（内置技能不可删）
    func deleteUserSkill(_ skill: Skill) {
        guard skill.source != "builtin" else {
            showToast("内置技能不可删除")
            return
        }
        let dir = URL(fileURLWithPath: skill.source).deletingLastPathComponent()
        _ = try? FileManager.default.removeItem(at: dir)
        Task {
            await skillRegistry.remove(skill.name)
            await self.refreshSkills()
            self.showToast("已删除技能：\(skill.name)")
        }
    }

    /// 技能名 slug 化（小写，仅保留字母/数字/中文/中划线/下划线）
    private static func skillSlug(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    deinit {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
    }

    // MARK: - 基础设施刷新

    func refreshPlugins() async {
        let infos = await pluginManager.list()
        plugins = infos.map { PluginDisplayItem(info: $0) }
            .sorted { !$0.isActive && $1.isActive }
    }

    // MARK: - 文件沙箱

    /// 当前文件沙箱根目录（UserDefaults 持久化；nil = 不限制）
    var sandboxRoot: String? {
        UserDefaults.standard.string(forKey: "sandboxRoot")
    }

    private static func makeSandboxFromSettings() -> PathSandbox? {
        UserDefaults.standard.string(forKey: "sandboxRoot").map { PathSandbox(allowedRoots: [$0]) }
    }

    /// 设置/清除沙箱根目录，并重新注册内置工具 + MCP 工具使其立即生效
    func setSandboxRoot(_ root: String?) {
        if let root {
            UserDefaults.standard.set(root, forKey: "sandboxRoot")
        } else {
            UserDefaults.standard.removeObject(forKey: "sandboxRoot")
        }
        Task {
            await self.toolRegistry.clear()
            for tool in BuiltinTools.makeAll(sandbox: root.map { PathSandbox(allowedRoots: [$0]) }) {
                await self.toolRegistry.register(tool)
            }
            for tool in await self.mcpManager.makeTools() {
                await self.toolRegistry.register(tool)
            }
            await self.refreshTools()
        }
    }

    func refreshTools() async {
        let schemas = await toolRegistry.schemas()
        let current = tools
        tools = schemas.map { schema in
            if let prev = current.first(where: { $0.id == schema.name }) {
                // 保留执行状态
                return ToolDisplayItem(id: prev.id, name: prev.name, description: prev.description,
                                       parameters: prev.parameters, category: prev.category,
                                       categoryDisplay: prev.categoryDisplay,
                                       isExecuted: prev.isExecuted, lastResult: prev.lastResult,
                                       executing: prev.executing)
            }
            return ToolDisplayItem(schema: schema)
        }
    }

    // MARK: - 会话（GRDB 持久化）

    private func loadSessionsFromDB() async {
        guard let db = sessionDB else { return }
        do {
            // 性能：列表只查元数据（单条 SQL），事件仅对选中会话按需拉取
            let loaded = try await db.loadSessions()
            // 合并语义：启动加载是异步的，加载窗口内用户可能已新建会话/开始对话，
            // 覆盖式赋值会把进行中的会话从列表与选中态清掉（P2 竞态）
            let inMemoryOnly = sessions.filter { s in
                !loaded.contains { $0.id == s.id }
            }
            sessions = inMemoryOnly + loaded
            // 当前选中仍有效（加载窗口内新建、或 DB 已有）→ 保留用户操作，不拉事件（messages 已持有）
            if let currentID = selectedSession?.id,
               sessions.contains(where: { $0.id == currentID }) {
                return
            }
            var first: SessionRecord?
            if let head = loaded.first, let full = try? await db.load(head.id) {
                first = full
            }
            selectedSession = first ?? loaded.first
            if let s = selectedSession {
                loadMessages(for: s)
            }
        } catch {
            generationError = "会话数据库加载失败：\(error.localizedDescription)"
        }
    }

    func createNewSession(silent: Bool = false) {
        let session = SessionRecord(metadata: SessionMetadata(cwd: URL(fileURLWithPath: NSHomeDirectory())))
        sessions.insert(session, at: 0)
        selectedSession = session
        messages.removeAll()
        generationError = nil
        lastUserMessage = ""
        persistSession()
        if !silent {
            showToast("已创建新对话")
        }
    }

    func deleteSession(_ session: SessionRecord) {
        dropChatLoop(sessionID: session.id)
        sessions.removeAll { $0.id == session.id }
        Task { [db = sessionDB] in
            if let db {
                try? await db.delete(session.id)
            }
        }
        if let data = try? JSONEncoder().encode(sessionTitles.filter { $0.key != session.id.rawValue }) {
            UserDefaults.standard.set(data, forKey: "sessionTitles")
        }
        if selectedSession?.id == session.id {
            selectedSession = nil
            messages.removeAll()
            if let s = sessions.first {
                presentSession(s)
            }
        }
        showToast("已删除对话")
    }

    func selectSession(_ session: SessionRecord) {
        generationError = nil
        presentSession(session)
    }

    /// 发布选中会话：完整记录直接渲染；仅元数据记录先拉事件再切换，
    /// 保证 selectedSession 永远不会指向空事件记录（persistSession 按 messages 重建事件，防误清空）
    private func presentSession(_ session: SessionRecord) {
        guard session.events.isEmpty, let db = sessionDB else {
            withAnimation(.smooth) { selectedSession = session }
            loadMessages(for: session)
            return
        }
        let id = session.id
        Task { [db] in
            guard let full = try? await db.load(id) else { return }
            if let idx = self.sessions.firstIndex(where: { $0.id == id }) {
                self.sessions[idx] = full
            }
            withAnimation(.smooth) { self.selectedSession = full }
            self.loadMessages(for: full)
        }
    }

    /// 从会话事件日志重建 UI 消息
    private func loadMessages(for session: SessionRecord) {
        var out: [ChatMessage] = []
        for event in session.events {
            switch event {
            case let .userMessage(m):
                if case let .text(t)? = m.content.first {
                    out.append(ChatMessage(id: UUID(), role: .user, content: t,
                                           timestamp: m.createdAt, status: .delivered))
                }
            case let .assistantMessage(m):
                if case let .text(t)? = m.content.first {
                    out.append(ChatMessage(id: UUID(), role: .assistant, content: t,
                                           timestamp: m.createdAt, status: .delivered))
                }
            default: break
            }
        }
        messages = out
    }

    /// 将当前 UI 消息持久化到会话事件日志
    private func persistSession() {
        guard let session = selectedSession else { return }
        var events: [SessionEvent] = []
        var turn = 0
        for m in messages where m.status == .delivered {
            if m.role == .user {
                turn += 1
                events.append(.userMessage(UserMessage(
                    content: [.text(m.content)]
                )))
            } else if m.role == .assistant {
                events.append(.assistantMessage(AssistantMessage(
                    turn: turn, step: 0,
                    content: [.text(m.content)],
                    provider: llmConfig.providerRaw, model: llmConfig.modelName
                )))
            }
        }
        let currentTurn = session.currentTurn
        let updated = SessionRecord(id: session.id, metadata: session.metadata,
                                    events: events, currentTurn: max(turn, currentTurn),
                                    status: .active)
        // 同步内存
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = updated
        }
        selectedSession = updated
        if let db = sessionDB {
            let db2 = db
            let s = updated
            Task { try? await db2.save(s) }
        }
    }

    // MARK: - 会话标题

    private static func loadTitles() -> [UUID: String] {
        guard let data = UserDefaults.standard.data(forKey: "sessionTitles"),
              let d = try? JSONDecoder().decode([UUID: String].self, from: data) else { return [:] }
        return d
    }

    private func saveTitles() {
        if let data = try? JSONEncoder().encode(sessionTitles) {
            UserDefaults.standard.set(data, forKey: "sessionTitles")
        }
    }

    func sessionTitle(for session: SessionRecord) -> String {
        if let t = sessionTitles[session.id.rawValue] {
            return t
        }
        if let first = messages.first(where: { $0.role == .user }) {
            return String(first.content.prefix(20))
        }
        for event in session.events {
            if case let .userMessage(m) = event, case let .text(t)? = m.content.first {
                return String(t.prefix(20))
            }
        }
        return "新对话"
    }

    /// 会话搜索：DB 正文检索 + 展示标题匹配（含改名，存 UserDefaults 不在 DB）并集，250ms 防抖
    func handleSessionSearch(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        searchTask?.cancel()
        guard !q.isEmpty else {
            searchResults = nil
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self, let db = sessionDB else { return }
            var hits: [SessionRecord] = await (try? db.search(query: q)) ?? []
            let hitIDs = Set(hits.map(\.id))
            let titleHits = sessions.filter { s in
                !hitIDs.contains(s.id) && self.sessionTitle(for: s).localizedCaseInsensitiveContains(q)
            }
            hits.append(contentsOf: titleHits)
            hits.sort { $0.metadata.createdAt > $1.metadata.createdAt }
            guard !Task.isCancelled else { return }
            DispatchQueue.main.async {
                self.searchResults = hits
            }
        }
    }

    private func autoTitle() {
        guard let session = selectedSession else { return }
        if sessionTitles[session.id.rawValue] != nil {
            return
        }
        if let first = messages.first(where: { $0.role == .user }) {
            sessionTitles[session.id.rawValue] = String(first.content.prefix(20))
            saveTitles()
        }
    }

    func renameSession(_ name: String) {
        guard let session = selectedSession else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        sessionTitles[session.id.rawValue] = name
        saveTitles()
        showToast("已重命名对话")
    }

    // MARK: - 模型 / LLM

    var hasAPIKey: Bool {
        if llmConfig.provider == .local {
            return true
        }
        return KeychainStorage.getAPIKey(forProvider: llmConfig.providerRaw) != nil
    }

    private func makeProvider(_ cfg: LLMConfig, key: String) -> any LLMProvider {
        if let factory = Self.providerFactory {
            return factory(cfg, key)
        }
        switch cfg.provider {
        case .openAI:
            return OpenAIAdapter(apiKey: key)
        case .deepSeek:
            return DeepSeekAdapter(apiKey: key)
        case .anthropic:
            return AnthropicAdapter(apiKey: key)
        case .local:
            let base = URL(string: cfg.localBaseURL) ?? URL(string: "http://localhost:11434/v1")!
            return LocalAdapter(apiKey: key.isEmpty ? "local" : key,
                                baseURL: base,
                                profile: ProviderProfile.local(forModel: cfg.modelName))
        }
    }

    // MARK: - 对话（真实 LLM 调用）

    func sendMessage(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        if selectedSession == nil {
            createNewSession(silent: true)
        }
        guard selectedSession != nil else { return }

        var userText = text
        if !attachments.isEmpty {
            let attached = attachments.map { a in
                "=== 附件：\(a.name)（\(a.path)）===\n\(a.content)\(a.truncated ? "\n…（内容已截断）" : "")"
            }.joined(separator: "\n\n")
            userText = (text.isEmpty ? "" : text + "\n\n") + attached
        }

        let userMessage = ChatMessage(id: UUID(), role: .user, content: userText,
                                      timestamp: Date(), status: .delivered)
        messages.append(userMessage)
        lastUserMessage = text.isEmpty ? "（附件）" : text
        attachments.removeAll()
        persistSession()
        autoTitle()

        isGenerating = true
        generationError = nil
        generateTask = Task { await self.performGeneration() }
    }

    /// 订阅 AgentLoop 实时工具进度（Codex 式：执行中显示当前工具名；完成/终答时清空）
    private func attachToolProgress(_ agent: AgentLoop) {
        agent.onProgress = { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch progress {
                case let .toolStarted(name):
                    activeToolName = name
                case .toolFinished, .finalAnswer:
                    activeToolName = nil
                }
            }
        }
    }

    // MARK: - 会话级 AgentLoop 缓存（跨轮工具上下文 + LRU 内存回收）

    /// 会话循环创建上下文（按值聚合，避免参数过多）
    private struct ChatLoopContext {
        let cfg: LLMConfig
        let key: String
        let seed: [LLM.Message]
        let systemPrompt: String?
    }

    /// 获取（或创建）会话的 AgentLoop：上下文指纹未变则复用（保留工具调用/结果 wire 历史）；
    /// 切换模型服务商/本地地址时重建并按文本种子重新播种
    private func obtainChatLoop(sessionID: SessionID, contextStamp: String,
                                context: ChatLoopContext) -> AgentLoop {
        if let existing = sessionLoops[sessionID], sessionLoopContext[sessionID] == contextStamp {
            touchSessionLoop(sessionID)
            return existing
        }
        let loop = AgentLoop(
            sessionID: sessionID,
            llm: makeProvider(context.cfg, key: context.key),
            tools: toolRegistry,
            model: context.cfg.modelName,
            systemPrompt: context.systemPrompt,
            history: context.seed
        )
        sessionLoops[sessionID] = loop
        sessionLoopContext[sessionID] = contextStamp
        sessionLoopOrder.append(sessionID)
        evictSessionLoops()
        return loop
    }

    private func touchSessionLoop(_ sessionID: SessionID) {
        if let idx = sessionLoopOrder.firstIndex(of: sessionID) {
            sessionLoopOrder.remove(at: idx)
            sessionLoopOrder.append(sessionID)
        }
    }

    /// LRU 淘汰：释放最旧会话的循环（循环无其他强引用，释放即回收内存）
    private func evictSessionLoops() {
        while sessionLoopOrder.count > Self.maxCachedLoops, let oldest = sessionLoopOrder.first {
            sessionLoopOrder.removeFirst()
            sessionLoops.removeValue(forKey: oldest)
            sessionLoopContext.removeValue(forKey: oldest)
        }
    }

    /// 丢弃会话缓存的循环（会话删除 / 显式重置上下文）
    func dropChatLoop(sessionID: SessionID) {
        sessionLoops.removeValue(forKey: sessionID)
        sessionLoopContext.removeValue(forKey: sessionID)
        sessionLoopOrder.removeAll { $0 == sessionID }
    }

    /// 测试观测：当前缓存的会话循环数
    var cachedLoopCountForTesting: Int {
        sessionLoops.count
    }

    private func performGeneration() async {
        let cfg = llmConfig
        let key = KeychainStorage.getAPIKey(forProvider: cfg.providerRaw) ?? ""

        if !hasAPIKey {
            let msg = "⚠️ 尚未配置 \(cfg.provider.displayName) 的 API Key。\n请打开「设置 → 模型服务」填写后重试；或切换到「本地模型」（Ollama / vLLM）。"
            messages.append(ChatMessage(id: UUID(), role: .assistant, content: msg,
                                        timestamp: Date(), status: .error))
            generationError = "未配置 API Key，无法发起真实请求。"
            isGenerating = false
            await notifyGeneration(error: "未配置 API Key")
            return
        }

        // 种子历史：最近 20 条 user/assistant 文本（仅新建循环时使用；复用的循环已持有完整 wire 历史）
        let newUserText = messages.last?.content ?? lastUserMessage
        let seed: [LLM.Message] = messages.dropLast().suffix(20).compactMap { m in
            guard m.status == .delivered, m.role == .user || m.role == .assistant else { return nil }
            return LLM.Message(role: m.role == .user ? .user : .assistant,
                               content: [.text(m.content)])
        }
        // 提示词工程层 + 记忆系统：系统提示词（内置模板/用户配置 + 相关长期记忆注入 {{#context}}）
        let systemPrompt = await buildSystemPrompt(model: cfg.modelName, userConfigured: cfg.systemPrompt)

        // 主聊天路径：会话级持久 AgentLoop（跨轮保留工具上下文；工具注册表 → 参数校验 → 执行 → 结果回填 → 收敛）
        let sessionID = selectedSession?.id ?? SessionID()
        let agent = obtainChatLoop(sessionID: sessionID,
                                   contextStamp: "\(cfg.providerRaw)|\(cfg.localBaseURL)",
                                   context: ChatLoopContext(cfg: cfg, key: key, seed: seed, systemPrompt: systemPrompt))
        chatAgent = agent
        defer {
            chatAgent = nil
            activeToolName = nil
        }
        // 每轮上下文刷新（模型切换 / 记忆注入变化）；历史完整保留
        await agent.setTurnContext(model: cfg.modelName, systemPrompt: systemPrompt)
        attachToolProgress(agent)

        // AgentLoop 内部统一捕获 LLM/工具异常并收敛为 result.error，此处无需 do/catch
        await agent.followup(UserMessage(content: [.text(newUserText)]))
        let result = await agent.whenIdle()
        if Task.isCancelled {
            isGenerating = false; return
        }
        if let errorText = result.error {
            messages.append(ChatMessage(id: UUID(), role: .assistant,
                                        content: "⚠️ 请求失败：\(errorText)",
                                        timestamp: Date(), status: .error))
            generationError = errorText
            isGenerating = false
            await notifyGeneration(error: errorText)
            return
        }
        // 工具轨迹 + 最终回答入会话
        guard let content = appendTurnResult(result) else {
            isGenerating = false
            return
        }
        isGenerating = false
        generationError = nil
        persistSession()
        // 记忆反馈闭环：蒸馏本轮交换（显式记住/纠正/决策/事实）→ 长期记忆
        await processMemoryFeedback(userText: lastUserMessage, assistantText: content)
        // 技能进化（Hermes 范式）：观测本轮任务真实工具序列，相似重复任务达阈值自动沉淀为技能
        await observeSkillEvolution(task: lastUserMessage, toolNames: Self.turnToolNames(result.steps))
        await notifyGeneration(error: nil)
    }

    /// 追加本轮 Agent 结果到会话：工具轨迹（每次工具调用一条可折叠 .tool 行，展示用，不进 LLM 历史）
    /// + 最终助手回答；无最终回答时返回 nil
    private func appendTurnResult(_ result: AgentResult) -> String? {
        for trace in result.toolTraces {
            let item = ToolTraceItem(id: trace.id, name: trace.name, arguments: trace.arguments,
                                     output: trace.output, ok: trace.ok)
            messages.append(ChatMessage(id: UUID(), role: .tool, content: "调用工具：\(trace.name)",
                                        timestamp: Date(), status: .delivered, toolTrace: [item]))
        }
        guard let final = result.messages.last else { return nil }
        let content = Self.textContent(of: final.content)
        messages.append(ChatMessage(id: UUID(), role: .assistant, content: content,
                                    timestamp: Date(), status: .delivered))
        return content
    }

    /// 从助手消息块提取文本（多块换行拼接）
    static func textContent(of blocks: [Session.ContentBlock]) -> String {
        blocks.compactMap { block -> String? in
            if case let .text(t) = block {
                return t
            }
            return nil
        }.joined(separator: "\n")
    }

    /// 单条助手消息中的工具名（按出现顺序去重）
    static func toolNames(in blocks: [Session.ContentBlock]) -> [String] {
        var seen = Set<String>()
        return blocks.compactMap { block -> String? in
            if case let .toolCall(call) = block {
                return seen.insert(call.name).inserted ? call.name : nil
            }
            return nil
        }
    }

    /// 整轮（全部步骤）的工具名序列（按步序、去重）
    static func turnToolNames(_ steps: [Session.AssistantMessage]) -> [String] {
        var seen = Set<String>()
        return steps.flatMap { Self.toolNames(in: $0.content) }.filter { seen.insert($0).inserted }
    }

    /// 系统提示词：用户显式配置优先；否则渲染内置 agent 模板并注入相关长期记忆
    private func buildSystemPrompt(model: String, userConfigured: String) async -> String? {
        if !userConfigured.isEmpty {
            return userConfigured
        }
        let promptEngine = await SharedPromptEngine.instance.get()
        var promptContext = PromptContext()
        if let memoryEngine, !lastUserMessage.isEmpty,
           let section = await memoryEngine.promptSection(query: lastUserMessage) {
            promptContext.blocks["context"] = section
        }
        return try? await promptEngine.renderSystemPrompt(template: PromptEngine.agentTemplate, model: model,
                                                          context: promptContext)
    }

    /// 记忆反馈闭环：对本轮交换做启发式蒸馏，命中规则则写入长期记忆并落盘
    private func processMemoryFeedback(userText: String, assistantText: String) async {
        guard let memoryEngine else { return }
        let sessionID = selectedSession?.id.rawValue.uuidString ?? "app"
        let exchanges = [MemoryExchange(role: .user, text: userText),
                         MemoryExchange(role: .assistant, text: assistantText)]
        let stored = await memoryEngine.consolidateSession(sessionID: sessionID, exchanges: exchanges)
        if stored > 0 {
            await memoryEngine.save()
        }
    }

    /// 技能进化观测：上报本轮任务与工具序列；相似重复任务达阈值自动生成技能
    /// （引擎/注册表为进程级共享：SharedSkillEvolution + skillRegistry，技能落 ~/.harness/skills）
    private func observeSkillEvolution(task: String, toolNames: [String]) async {
        var seen = Set<String>()
        let deduped = toolNames.filter { seen.insert($0).inserted }
        let sessionID = selectedSession?.id.rawValue.uuidString ?? "app"
        let engine = await SharedSkillEvolution.shared.get(registry: skillRegistry)
        await engine.observe(sessionID: sessionID, task: task, toolNames: deduped, succeeded: true)
        _ = await engine.evaluate()
    }

    /// 停止生成（真实取消 URLSession 请求）
    func stopGenerating() {
        generateTask?.cancel()
        generateTask = nil
        // 同步取消 AgentLoop：whenIdle 立即返回，在途 LLM 调用后台自行完成（不再阻塞）
        Task { [chatAgent] in await chatAgent?.cancel(keepInbox: false) }
        isGenerating = false
        showToast("已停止生成")
    }

    func retryLastMessage() {
        guard !lastUserMessage.isEmpty else { return }
        if let lastIdx = messages.lastIndex(where: { $0.status == .error }) {
            messages.remove(at: lastIdx)
        }
        generationError = nil
        sendMessage(lastUserMessage)
    }

    // MARK: - 插件（真实 PluginManager）

    func togglePlugin(_ plugin: PluginDisplayItem) {
        Task {
            if plugin.isActive {
                do {
                    try await pluginManager.uninstall(PluginID(plugin.id))
                    showToast("已停用插件：\(plugin.name)")
                } catch {
                    showToast("停用失败：\(error.localizedDescription)")
                }
            } else {
                guard let pluginAny = makeBuiltInPlugin(plugin.id) else {
                    showToast("未知插件，无法启用")
                    return
                }
                do {
                    try await pluginManager.install(pluginAny)
                    showToast("已启用插件：\(plugin.name)")
                } catch {
                    showToast("启用失败：\(error.localizedDescription)")
                }
            }
            await refreshPlugins()
        }
    }

    // MARK: - 进程隔离（XPC worker）

    /// 内置插件工厂（id 限定为已实现的两个内置插件）
    private func makeBuiltInPlugin(_ id: String) -> (any Plugin)? {
        switch id {
        case "file-system": BuiltInFilesystemPlugin()
        case "terminal": BuiltInTerminalPlugin()
        default: nil
        }
    }

    /// worker 二进制路径（与 .app 同目录，debug 构建在 .build/.../debug）
    var xpcWorkerPath: String? {
        let appDir = URL(fileURLWithPath: Bundle.main.bundlePath).deletingLastPathComponent()
        let worker = appDir.appendingPathComponent("HarnessPluginWorker")
        return FileManager.default.isExecutableFile(atPath: worker.path) ? worker.path : nil
    }

    private func persistIsolation() {
        UserDefaults.standard.set(Array(isolatedPluginIDs), forKey: "isolatedPlugins")
    }

    /// 启动恢复：上次隔离的插件重新挂到 worker（worker 不可用时静默回退进程内）
    private func restoreIsolatedPlugins() async {
        let ids = UserDefaults.standard.stringArray(forKey: "isolatedPlugins") ?? []
        guard !ids.isEmpty else { return }
        var restored: [String] = []
        for idStr in ids {
            let ok = await installIsolated(idStr)
            if ok {
                restored.append(idStr)
            }
        }
        if restored != ids {
            UserDefaults.standard.set(restored, forKey: "isolatedPlugins")
        }
    }

    /// 把内置插件改挂到 XPC worker（先卸进程内实例，再安装 proxy）
    private func installIsolated(_ id: String) async -> Bool {
        guard let workerPath = xpcWorkerPath,
              let manifest = makeBuiltInPlugin(id)?.manifest
        else { return false }
        guard await xpcHost.ensureWorkerRegistered(workerPath: workerPath),
              await xpcHost.connect(),
              await xpcHost.isAlive(timeout: 5),
              let proxy = await xpcHost.makeProxy(manifest: manifest)
        else { return false }
        let pluginID = PluginID(id)
        do {
            let installed = await pluginManager.list()
            if installed.contains(where: { $0.id == pluginID }) {
                try await pluginManager.uninstall(pluginID)
            }
            try await pluginManager.install(proxy)
            return true
        } catch {
            return false
        }
    }

    /// 切换插件运行模式：进程内 <-> XPC 隔离进程
    func toggleIsolation(for plugin: PluginDisplayItem) {
        Task {
            let pluginID = PluginID(plugin.id)
            if isolatedPluginIDs.contains(plugin.id) {
                do {
                    try await pluginManager.uninstall(pluginID)
                    try await pluginManager.install(makeBuiltInPlugin(plugin.id) ?? BuiltInFilesystemPlugin())
                    isolatedPluginIDs.remove(plugin.id)
                    persistIsolation()
                    showToast("插件\(plugin.name)已恢复进程内运行")
                } catch {
                    showToast("恢复失败：\(error.localizedDescription)")
                }
            } else {
                guard await installIsolated(plugin.id) else {
                    showToast("隔离进程不可用（worker 缺失或注册失败）")
                    return
                }
                isolatedPluginIDs.insert(plugin.id)
                persistIsolation()
                showToast("插件\(plugin.name)已启用进程隔离（崩溃不影响主进程）")
            }
            await refreshPlugins()
        }
    }

    // MARK: - 系统通知（生成完成/失败）

    var notificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "notificationsEnabled")
        Task {
            await notificationCenter.setEnabled(enabled)
            if enabled {
                _ = await notificationCenter.ensureAuthorization()
            }
        }
    }

    private func notifyGeneration(error: String?) async {
        guard let session = selectedSession else { return }
        let title = sessionTitles[session.id.rawValue]
            ?? session.metadata.cwd.lastPathComponent
        await notificationCenter.postGenerationFinished(sessionTitle: title, error: error)
    }

    // MARK: - 插件市场（真实 PluginMarketplace 编排）

    func refreshMarketplace() async {
        await marketplace.refresh()
        let entries = await marketplace.browse()
        marketplaceEntries = entries.map { MarketplaceDisplayItem(entry: $0) }
    }

    func installFromMarket(_ item: MarketplaceDisplayItem) {
        Task {
            do {
                _ = try await marketplace.install(PluginID(item.id))
                showToast("已从市场安装插件：\(item.name)")
            } catch {
                showToast("安装失败：\(error.localizedDescription)")
            }
            await refreshMarketplace()
            await refreshPlugins()
        }
    }

    func updateFromMarket(_ item: MarketplaceDisplayItem) {
        Task {
            do {
                _ = try await marketplace.upgrade(PluginID(item.id))
                showToast("已更新插件：\(item.name)")
            } catch {
                showToast("更新失败：\(error.localizedDescription)")
            }
            await refreshMarketplace()
            await refreshPlugins()
        }
    }

    func uninstallFromMarket(_ item: MarketplaceDisplayItem) {
        Task {
            do {
                try await marketplace.uninstall(PluginID(item.id))
                showToast("已从市场卸载插件：\(item.name)")
            } catch {
                showToast("卸载失败：\(error.localizedDescription)")
            }
            await refreshMarketplace()
            await refreshPlugins()
        }
    }

    // MARK: - 多 Agent 协作（真实 SubagentCoordinator 编排）

    /// 历史文件路径覆盖（单元测试隔离用；生产为 nil）
    static var subagentHistoryURLOverride: URL?

    /// 通知服务工厂覆盖（单元测试隔离用；生产为 nil → 系统通知）
    static var notificationServiceFactory: (@Sendable () -> any NotificationService)?
    /// 模型供应商工厂覆盖（单元测试隔离用；生产为 nil → 真实 API 适配器）
    static var providerFactory: (@Sendable (LLMConfig, String) -> (any LLMProvider))?

    /// 子任务历史文件（~/Library/Application Support/Harness/，与 XPC plist 同目录约定）
    static var subagentHistoryURL: URL {
        if let override = subagentHistoryURLOverride {
            return override
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Harness", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("subagent_history.json")
    }

    static func loadSubagentHistoryItems() -> [SubagentDisplayItem] {
        SubagentHistoryStore.load(url: subagentHistoryURL).map { SubagentDisplayItem(from: $0) }
    }

    func refreshSubagents() async {
        let states = await subagentCoordinator.allStates()
        let live = states.map { SubagentDisplayItem(state: $0) }
        var history = SubagentHistoryStore.load(url: Self.subagentHistoryURL)
        let knownIDs = Set(history.map(\.id))
        // 新到终态的条目写入历史（去重、最新在前、带上限）
        let fresh = live.filter { $0.phase.isTerminal && !knownIDs.contains($0.id) }
        if !fresh.isEmpty {
            history = Array((fresh.map(\.toHistory) + history).prefix(SubagentHistoryStore.defaultCap))
            SubagentHistoryStore.save(history, url: Self.subagentHistoryURL)
        }
        let liveIDs = Set(live.map(\.id))
        subagents = live + history.filter { !liveIDs.contains($0.id) }.map { SubagentDisplayItem(from: $0) }
    }

    func spawnSubagent(name: String, task: String, timeout: TimeInterval) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !task.isEmpty else {
            showToast("任务名称与任务内容不能为空")
            return
        }
        guard hasAPIKey else {
            showToast("请先在设置中配置模型 API Key")
            return
        }
        let key = KeychainStorage.getAPIKey(forProvider: llmConfig.providerRaw) ?? ""
        let provider = makeProvider(llmConfig, key: key)
        let model = llmConfig.modelName
        let tools = subagentToolRegistry
        Task {
            // 提示词工程层：子 Agent 角色模板（模型差异化适配；失败回退原文案）
            let promptEngine = await SharedPromptEngine.instance.get()
            let subagentPrompt = await (try? promptEngine.renderSystemPrompt(
                template: PromptEngine.subagentTemplate, model: model
            ))
                ?? "你是子任务执行 Agent：直接完成给定任务，输出简洁结果，不要反问。"
            let agent = AgentLoop(
                sessionID: SessionID(),
                llm: provider,
                tools: tools,
                model: model,
                systemPrompt: subagentPrompt
            )
            let id = await subagentCoordinator.spawn(agent: agent, spec: SubagentSpec(name: name, task: task, timeout: timeout))
            showToast("已派生子任务：\(name)")
            let state = await subagentCoordinator.waitFor(id)
            await notifySubagentFinished(state)
        }
    }

    /// 子任务到达终态 → 系统通知（复用 Notifications 包；取消为用户主动操作，不通知）
    private func notifySubagentFinished(_ state: SubagentState) async {
        guard let title = state.phase.notificationTitle else { return }
        var detail = "「\(state.name)」"
        switch state.phase {
        case .succeeded:
            if let first = state.result?.messages.first {
                let text = first.content.compactMap { block -> String? in
                    if case let .text(s) = block {
                        return s
                    }
                    return nil
                }.joined()
                detail += String(text.prefix(60))
            }
        case .failed, .timedOut:
            detail += state.error ?? "未知错误"
        default:
            break
        }
        await notificationCenter.post(event: title, detail: detail)
    }

    /// 对话页「派生」按钮：当前输入（为空时退回最后一条用户消息）→ 子任务
    func spawnSubagentFromChat(_ draftText: String) {
        let draft = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = draft.isEmpty ? lastUserMessage : draft
        guard !task.isEmpty else {
            showToast("没有可派生的输入内容")
            return
        }
        spawnSubagent(name: String(task.prefix(12)), task: task, timeout: 120)
    }

    func cancelSubagent(_ item: SubagentDisplayItem) {
        guard let raw = UUID(uuidString: item.id) else { return }
        Task {
            await subagentCoordinator.cancel(SubagentID(rawValue: raw))
        }
    }

    func clearFinishedSubagents() {
        Task {
            let removed = await subagentCoordinator.removeFinished()
            let historyCount = SubagentHistoryStore.load(url: Self.subagentHistoryURL).count
            SubagentHistoryStore.save([], url: Self.subagentHistoryURL)
            await refreshSubagents()
            let total = removed + historyCount
            if total > 0 {
                showToast("已清理 \(total) 个完成的子任务")
            }
        }
    }

    // MARK: - 工具（真实 ToolRegistry 执行）

    func executeTool(at index: Int, withParams params: String) {
        guard index < tools.count else { return }
        let tool = tools[index]
        tools[index] = ToolDisplayItem(
            id: tool.id, name: tool.name, description: tool.description,
            parameters: tool.parameters, category: tool.category,
            categoryDisplay: tool.categoryDisplay, isExecuted: tool.isExecuted,
            lastResult: tool.lastResult, executing: true
        )
        let sessionId = selectedSession?.id ?? SessionID()
        Task {
            let result: String
            do {
                guard let toolImpl = await self.toolRegistry.tool(named: tool.name) else {
                    result = "⚠️ 工具 \(tool.name) 未注册"
                    return
                }
                let context = ToolRunContext(
                    signal: CancellationToken(),
                    sessionID: sessionId,
                    metadata: ["source": "ui"]
                )
                let res = try await toolImpl.execute(Self.parseParams(params), context: context)
                let text = res.content.compactMap { block -> String? in
                    if case let .text(t) = block {
                        return t
                    }
                    return nil
                }.joined(separator: "\n")
                result = res.error.map { "❌ \($0.message)\n\n\(text)" } ?? text
            } catch {
                result = "❌ 执行异常：\(error.localizedDescription)"
            }
            await MainActor.run {
                guard index < self.tools.count else { return }
                let t = self.tools[index]
                self.tools[index] = ToolDisplayItem(
                    id: t.id, name: t.name, description: t.description,
                    parameters: t.parameters, category: t.category,
                    categoryDisplay: t.categoryDisplay, isExecuted: true,
                    lastResult: result, executing: false
                )
            }
        }
    }

    /// 解析用户输入的 JSON 参数（容错：非 JSON 时整体作为 cmd/path）
    static func parseParams(_ raw: String) -> [String: String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [:] }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj.compactMapValues { v in
                if let s = v as? String {
                    return s
                }
                if let n = v as? NSNumber {
                    return n.stringValue
                }
                return nil
            }
        }
        // 容错：整体视为 cmd
        return ["cmd": trimmed]
    }

    func clearToolResult(at index: Int) {
        guard index < tools.count else { return }
        let tool = tools[index]
        tools[index] = ToolDisplayItem(
            id: tool.id, name: tool.name, description: tool.description,
            parameters: tool.parameters, category: tool.category,
            categoryDisplay: tool.categoryDisplay, isExecuted: false,
            lastResult: nil, executing: false
        )
    }

    // MARK: - 附件（真实文件读取）

    func attachFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "添加"
        panel.message = "选择要附加到对话的文件（文本类文件，单个 ≤ 200KB）"
        guard panel.runModal() == .OK else { return }
        var newOnes: [FileAttachment] = []
        for url in panel.urls.prefix(5) {
            guard let data = try? Data(contentsOf: url), data.count <= 200_000,
                  let text = String(data: data, encoding: .utf8)
            else {
                showToast("跳过 \(url.lastPathComponent)（非 UTF-8 文本或超过 200KB）")
                continue
            }
            newOnes.append(FileAttachment(name: url.lastPathComponent, path: url.path,
                                          content: text, truncated: text.count > 50000))
        }
        if !newOnes.isEmpty {
            attachments.append(contentsOf: newOnes)
            showToast("已添加 \(newOnes.count) 个附件")
        }
    }

    func removeAttachment(_ id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    // MARK: - 工具栏操作（全部真实功能）

    private var tsFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }

    /// 复制对话到剪贴板
    func shareChat() {
        guard !messages.isEmpty else { showToast("当前没有可复制的内容"); return }
        let fmt = tsFormatter
        let text = messages.map { "[\(fmt.string(from: $0.timestamp))] \($0.role.displayName)：\n\($0.content)" }
            .joined(separator: "\n\n---\n\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        showToast("对话已复制到剪贴板")
    }

    /// 导出对话为 Markdown 文件
    func exportChat() {
        guard !messages.isEmpty else { showToast("当前没有可导出的内容"); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = []
        let nameFmt = DateFormatter()
        nameFmt.dateFormat = "yyyyMMdd-HHmm"
        panel.nameFieldStringValue = "Harness对话-\(nameFmt.string(from: Date())).md"
        panel.message = "选择导出位置"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var md = "# Harness 对话导出\n\n> 模型：\(llmConfig.provider.displayName) / \(llmConfig.modelName)\n> 导出时间：\(Date.now.formatted())\n\n"
        for m in messages {
            md += "## \(m.role.displayName)（\(tsFormatter.string(from: m.timestamp))）\n\n\(m.content)\n\n"
        }
        do {
            try md.write(to: url, atomically: true, encoding: .utf8)
            showToast("已导出到 \(url.lastPathComponent)")
        } catch {
            showToast("导出失败：\(error.localizedDescription)")
        }
    }

    /// 清空当前对话
    func clearChat() {
        messages.removeAll()
        generationError = nil
        lastUserMessage = ""
        if let session = selectedSession {
            if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[idx] = SessionRecord(id: session.id, metadata: session.metadata,
                                              events: [], currentTurn: session.currentTurn)
                selectedSession = sessions[idx]
                if let db = sessionDB {
                    let s = sessions[idx]; let db2 = db
                    Task { try? await db2.save(s) }
                }
            }
        }
        showToast("已清空对话")
    }

    // MARK: - Toast

    func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            MainActor.assumeIsolated {
                if self?.toastMessage == message {
                    self?.toastMessage = nil
                }
            }
        }
    }
}

// swiftlint:enable file_length type_body_length
