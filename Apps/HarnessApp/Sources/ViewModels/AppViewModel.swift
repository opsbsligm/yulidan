import Agent
import AppKit
import Foundation
import HarnessCore
import LLM
import Sandbox

// 技术债：本文件/类超过长度阈值，计划拆分为 会话管理 / 生成流程 / 设置 三个 ViewModel（见 docs/CODE_REVIEW.md）
// swiftlint:disable file_length type_body_length
import MCP
import ServiceContainer
import Session
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
    @Published var generationError: String?
    @Published var lastUserMessage = ""
    @Published var attachments: [FileAttachment] = []

    /// 模型
    @Published var llmConfig: LLMConfig

    // 插件 / 工具
    @Published var plugins: [PluginDisplayItem] = []
    @Published var tools: [ToolDisplayItem] = []

    // 基础设施（真实组件）
    let sessionDB: SessionDB?
    let pluginManager: PluginManager
    let toolRegistry: ToolRegistry
    let mcpManager: MCPServerManager

    private var generateTask: Task<Void, Never>?
    private var sessionTitles: [UUID: String] = [:]
    private nonisolated(unsafe) var configObserver: (any NSObjectProtocol)?

    // MARK: - 初始化

    init() {
        let container = ServiceContainer()
        let eventBus = EventBus()
        pluginManager = PluginManager(container: container, eventBus: eventBus,
                                      harnessVersion: PluginVersion(major: 0, minor: 1, patch: 0))
        toolRegistry = ToolRegistry()
        mcpManager = MCPServerManager()
        llmConfig = LLMConfig.load()
        sessionDB = try? SessionDB()
        sessionTitles = Self.loadTitles()

        // 注册真实内置工具（按设置注入文件沙箱）+ MCP 演示服务器（内存客户端，处理器为真实能力）
        Task {
            for tool in BuiltinTools.makeAll(sandbox: Self.makeSandboxFromSettings()) {
                await self.toolRegistry.register(tool)
            }
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
            await self.mcpManager.register(demo, descriptor: MCPServer(name: "local", transport: "in-memory"))
            for tool in await self.mcpManager.makeTools() {
                await self.toolRegistry.register(tool)
            }
            await self.refreshTools()
        }

        // 安装真实内置插件
        Task {
            do {
                try await self.pluginManager.install(BuiltInFilesystemPlugin())
                try await self.pluginManager.install(BuiltInTerminalPlugin())
            } catch {
                // 安装失败不阻塞启动，列表仍会展示真实状态
            }
            await self.refreshPlugins()
        }

        // 加载持久化会话
        Task { await self.loadSessionsFromDB() }

        // 监听模型配置变更（设置页保存后同步）
        configObserver = NotificationCenter.default.addObserver(
            forName: LLMConfig.configDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.llmConfig = LLMConfig.load()
            }
        }
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
            let loaded = try await db.loadAll()
            sessions = loaded
            selectedSession = loaded.first
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
            selectedSession = sessions.first
            if let s = selectedSession {
                loadMessages(for: s)
            } else {
                messages.removeAll()
            }
        }
        showToast("已删除对话")
    }

    func selectSession(_ session: SessionRecord) {
        withAnimation(.smooth) { selectedSession = session }
        loadMessages(for: session)
        generationError = nil
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
        switch cfg.provider {
        case .openAI:
            return OpenAIAdapter(apiKey: key)
        case .deepSeek:
            return DeepSeekAdapter(apiKey: key)
        case .anthropic:
            return AnthropicAdapter(apiKey: key)
        case .local:
            let base = URL(string: cfg.localBaseURL) ?? URL(string: "http://localhost:11434/v1")!
            return LocalAdapter(apiKey: key.isEmpty ? "local" : key, baseURL: base)
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

    private func performGeneration() async {
        let cfg = llmConfig
        let key = KeychainStorage.getAPIKey(forProvider: cfg.providerRaw) ?? ""

        if !hasAPIKey {
            let msg = "⚠️ 尚未配置 \(cfg.provider.displayName) 的 API Key。\n请打开「设置 → 模型服务」填写后重试；或切换到「本地模型」（Ollama / vLLM）。"
            messages.append(ChatMessage(id: UUID(), role: .assistant, content: msg,
                                        timestamp: Date(), status: .error))
            generationError = "未配置 API Key，无法发起真实请求。"
            isGenerating = false
            return
        }

        let history: [LLM.Message] = messages.suffix(20).compactMap { m in
            guard m.status == .delivered, m.role == .user || m.role == .assistant else { return nil }
            return LLM.Message(role: m.role == .user ? .user : .assistant,
                               content: [.text(m.content)])
        }
        let request = LLMRequest(
            model: cfg.modelName,
            messages: history,
            systemPrompt: cfg.systemPrompt.isEmpty ? nil : cfg.systemPrompt,
            maxTokens: cfg.maxTokens
        )
        let provider = makeProvider(cfg, key: key)

        do {
            let resp = try await provider.request(request)
            if Task.isCancelled {
                isGenerating = false; return
            }
            let content = resp.content.compactMap { block -> String? in
                if case let .text(t) = block {
                    return t
                }
                return nil
            }.joined(separator: "\n")
            messages.append(ChatMessage(id: UUID(), role: .assistant, content: content,
                                        timestamp: Date(), status: .delivered))
            isGenerating = false
            generationError = nil
            persistSession()
        } catch is CancellationError {
            isGenerating = false
        } catch let e as URLError where e.code == .cancelled {
            isGenerating = false
        } catch {
            if Task.isCancelled {
                isGenerating = false; return
            }
            let desc = (error as? LLMError)?.errorDescription ?? error.localizedDescription
            messages.append(ChatMessage(id: UUID(), role: .assistant,
                                        content: "⚠️ 请求失败：\(desc)",
                                        timestamp: Date(), status: .error))
            generationError = desc
            isGenerating = false
        }
    }

    /// 停止生成（真实取消 URLSession 请求）
    func stopGenerating() {
        generateTask?.cancel()
        generateTask = nil
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
                let pluginAny: any Plugin
                switch plugin.id {
                case "file-system": pluginAny = BuiltInFilesystemPlugin()
                case "terminal": pluginAny = BuiltInTerminalPlugin()
                default:
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
