import Foundation
import LLM
import ServiceContainer
import Session
import Tools

/// 内存/性能探针 — 在 leaks 下反复执行应用核心路径：
/// 1. SessionDB 保存/加载/删除（GRDB 持久化）
/// 2. ToolRegistry 注册 + list_files 执行
/// 3. PluginManager 安装/停用（内置插件同款实现）
@main
struct MemProbe {
    struct ProbePlugin: Plugin {
        let manifest = PluginManifest(
            id: PluginID("probe"), name: "探针",
            version: PluginVersion(major: 1, minor: 0, patch: 0),
            description: "memprobe",
            minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0),
            permissions: [.filesystemRead]
        )
        func initialize(context _: PluginContext) async throws {}
        func start(context _: PluginContext) async throws {}
        func stop(context _: PluginContext) async {}
    }

    static func main() async {
        let iterations = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 200 : 200
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("memprobe-\(UUID().uuidString).sqlite")
        let start = Date()
        do {
            // 1) 会话持久化
            let db = try SessionDB(dbURL: dbURL)
            var alive: [SessionID] = []
            for i in 0 ..< iterations {
                var s = SessionRecord(id: SessionID(),
                                      metadata: SessionMetadata(cwd: URL(fileURLWithPath: "/tmp")))
                s.append(.userMessage(UserMessage(content: [.text("probe-\(i)")])))
                s.append(.assistantMessage(AssistantMessage(
                    turn: 1, step: 0, content: [.text("ok-\(i)")],
                    provider: "deepseek", model: "deepseek-chat"
                )))
                s.currentTurn = 1
                try await db.save(s)
                alive.append(s.id)
                // 与 App 启动路径同款：元数据快速列表 + 选中会话完整加载
                _ = try await db.loadSessions()
                _ = try await db.load(alive.last!)
                if i % 20 == 0, let old = alive.first {
                    alive.removeFirst()
                    try await db.delete(old)
                }
            }
            for id in alive {
                try await db.delete(id)
            }

            // 2) 工具执行
            let reg = ToolRegistry()
            for t in BuiltinTools.makeAll() {
                await reg.register(t)
            }
            let listTool = await reg.tool(named: "list_files")!
            let ctx = ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
            for _ in 0 ..< iterations {
                _ = try await listTool.execute(["path": "/tmp", "limit": "20"], context: ctx)
            }

            // 3) 插件生命周期
            let container = ServiceContainer()
            let bus = EventBus()
            let pm = PluginManager(container: container, eventBus: bus)
            for _ in 0 ..< iterations {
                try await pm.install(ProbePlugin())
                _ = await pm.list()
                try await pm.uninstall(PluginID("probe"))
            }

            print("MemProbe OK: \(iterations) iterations in \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
        } catch {
            print("MemProbe FAILED: \(error)")
            exit(1)
        }
        try? FileManager.default.removeItem(at: dbURL)
    }
}
