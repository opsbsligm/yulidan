import Foundation
@testable import HarnessApp
import LLM
import MCP
import Memory
import RAG
import Testing
import Workspace

// MARK: - P0.1.5 工作区运行时接线（2026-08-30 起纯本地单根：SSO/iCloud 模块整体移除）

//
// 隔离纪律（与既有 App 套件一致）：
// - 全部目录走每用例独立临时目录；不触碰真实 DB / ~/.harness
// - AppViewModel 经 init 缝注入 workspaceRouter / sharedRAG / sessionDBURL / mcpConfigURLOverride
// - .serialized：AppViewModel 套件并行时 @MainActor await 点交错，串行最稳

/// 每用例独立：临时根目录（本地根）
@MainActor
final class AppWorkspaceFixture {
    let tempDir: URL
    let localRoot: URL
    /// 全局 UserDefaults 沙箱设置的隔离（防跨 suite 串扰 / 磁盘持久化残留）
    private let prevSandboxRoot: String?

    init() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ws-routing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        localRoot = tempDir.appendingPathComponent("LocalRoot", isDirectory: true)
        // 沙箱设置全局生效且持久化：fixture 一律移除，cleanup 恢复原值（VM 测试 hermetic）
        prevSandboxRoot = UserDefaults.standard.string(forKey: "sandboxRoot")
        UserDefaults.standard.removeObject(forKey: "sandboxRoot")
    }

    var router: WorkspaceRouter {
        WorkspaceRouter(provider: WorkspaceRootProvider(localRoot: localRoot))
    }

    func cleanup() {
        if let prevSandboxRoot {
            UserDefaults.standard.set(prevSandboxRoot, forKey: "sandboxRoot")
        } else {
            UserDefaults.standard.removeObject(forKey: "sandboxRoot")
        }
        UserDefaults.standard.synchronize()
        try? FileManager.default.removeItem(at: tempDir)
    }
}

private func settle(_ ms: Int = 200) async throws {
    try await Task.sleep(for: .milliseconds(ms))
}

// MARK: - 套件 1：WorkspaceRouter 纯路由（本地单根）

@MainActor
@Suite("P0.1.5 WorkspaceRouter 路由", .serialized)
struct WorkspaceRouterTests {
    @Test("本地根：目录集路由 + 骨架物化")
    func localModeRoutes() throws {
        let fx = try AppWorkspaceFixture()
        defer { fx.cleanup() }
        let router = fx.router
        #expect(router.current.kind == .local)
        #expect(router.agentOutputs == fx.localRoot.appendingPathComponent("agents", isDirectory: true))
        #expect(router.ragIndexURL == fx.localRoot.appendingPathComponent("rag/index.json"))
        #expect(router.pluginMetaURL == fx.localRoot.appendingPathComponent("plugins-meta/installed.json"))
        #expect(router.themeResources == fx.localRoot.appendingPathComponent("themes", isDirectory: true))
        #expect(router.memoryStoreURL == fx.localRoot.appendingPathComponent("memory/longterm.json"))
        for dir in WorkspaceLayout.allDirectories {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(
                atPath: fx.localRoot.appendingPathComponent(dir).path, isDirectory: &isDir
            )
            #expect(isDir.boolValue, "本地根缺失子目录：\(dir)")
        }
    }

    @Test("sessionCwd 位于 agentOutputs/<sessionID>")
    func sessionCwdShape() throws {
        let fx = try AppWorkspaceFixture()
        defer { fx.cleanup() }
        let router = fx.router
        let sid = UUID()
        let cwd = router.sessionCwd(sid)
        #expect(cwd == fx.localRoot.appendingPathComponent("agents/\(sid.uuidString)", isDirectory: true))
    }
}

// MARK: - 套件 2：PluginMetadataStore

@Suite("P0.1.5 插件元数据清单")
struct PluginMetadataStoreTests {
    @Test("round-trip：保存 → 加载等价")
    func roundTrip() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meta-\(UUID().uuidString)/installed.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let manifest = PluginMetaManifest(plugins: [
            PluginMetaEntry(id: "a", name: "A", version: "1.0.0", origin: .builtin, enabled: true),
            PluginMetaEntry(id: "b", name: "B", version: "1.0.0", origin: .localMCP, enabled: true,
                            localPath: "/usr/local/bin/b", mcpCommand: ["/usr/local/bin/b", "--x"]),
        ])
        try PluginMetadataStore.save(manifest, to: url)
        #expect(PluginMetadataStore.load(from: url) == manifest)
    }

    @Test("缺失 / 损坏 / 版本不符 → 空清单（不污染运行时）")
    func corruptTolerance() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meta-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let missing = base.appendingPathComponent("none/installed.json")
        #expect(PluginMetadataStore.load(from: missing).plugins.isEmpty)

        let corrupt = base.appendingPathComponent("corrupt.json")
        try Data("not-json".utf8).write(to: corrupt)
        #expect(PluginMetadataStore.load(from: corrupt).plugins.isEmpty)

        let badVersion = base.appendingPathComponent("badver.json")
        struct BadVersionPayload: Codable {
            var version: Int
            var plugins: [PluginMetaEntry]
        }
        let data = try JSONEncoder().encode(BadVersionPayload(version: 99, plugins: []))
        try data.write(to: badVersion)
        #expect(PluginMetadataStore.load(from: badVersion).plugins.isEmpty)
    }

    @Test("原子保存：重复覆盖不残留临时文件")
    func atomicOverwrite() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meta-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("installed.json")
        for i in 0 ..< 3 {
            try PluginMetadataStore.save(PluginMetaManifest(plugins: [
                PluginMetaEntry(id: "p\(i)", name: "P\(i)", version: "1.0.0", origin: .builtin, enabled: true),
            ]), to: url)
        }
        let leftover = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix(".installed-") }
        #expect(leftover.isEmpty)
        #expect(PluginMetadataStore.load(from: url).plugins.map(\.id) == ["p2"])
    }
}

// MARK: - 套件 4：AppViewModel 工作区接线场景

/// 全缝注入：临时 skill/DB/mcpConfig + 本地根路由 + 独立 RAG 实例（e2e 拆分文件复用）
@MainActor
func makeWorkspaceVM(_ fx: AppWorkspaceFixture) -> (vm: AppViewModel, mcpConfigURL: URL) {
    UserDefaults.standard.removeObject(forKey: ThemePluginManager.activeKey)
    let mcpConfigURL = fx.tempDir.appendingPathComponent("mcp/servers.json")
    let ragIndex = fx.tempDir.appendingPathComponent("rag-instance/index.json")
    let memStore = fx.tempDir.appendingPathComponent("memory-instance/longterm.json")
    let vm = AppViewModel(
        skillUserDirectory: fx.tempDir.appendingPathComponent("skills"),
        sessionDBURL: fx.tempDir.appendingPathComponent("sessions.sqlite"),
        mcpConfigURLOverride: mcpConfigURL,
        workspaceRouter: fx.router,
        sharedRAG: SharedRAGEngine(indexURL: ragIndex),
        sharedMemory: SharedMemoryEngine(fileURL: memStore),
        legacyMemoryURLOverride: fx.tempDir.appendingPathComponent("legacy-none/longterm.json")
    )
    return (vm, mcpConfigURL)
}

@MainActor
@Suite("AppViewModel P0.1.5 工作区接线", .serialized)
struct AppViewModelWorkspaceRoutingTests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    @Test("新会话 cwd = 工作区/agents/<sessionID>（本地根）")
    func newSessionCwdRoutesToWorkspace() throws {
        let fx = try AppWorkspaceFixture()
        defer { fx.cleanup() }
        let (vm, _) = makeWorkspaceVM(fx)
        vm.createNewSession(silent: true)
        guard let session = vm.sessions.first else {
            Issue.record("未创建会话")
            return
        }
        let expected = fx.localRoot.appendingPathComponent(
            "agents/\(session.id.rawValue.uuidString)", isDirectory: true
        )
        #expect(session.metadata.cwd == expected)
    }

    @Test("MCP 导入写元数据清单至本地工作区（本地单根，无跨根对账语义）")
    func mcpMetadataPersistsToWorkspace() async throws {
        let fx = try AppWorkspaceFixture()
        defer { fx.cleanup() }
        let (vm, mcpConfigURL) = makeWorkspaceVM(fx)

        // 导入真实可执行二进制（脚本，连接会失败但配置落 servers.json + 元数据清单落工作区）
        let fakeBin = fx.tempDir.appendingPathComponent("fake-mcp-bin")
        try Data("#!/bin/sh\nexit 1\n".utf8).write(to: fakeBin)
        let perms: [FileAttributeKey: Int] = [.posixPermissions: 0o755]
        try FileManager.default.setAttributes(perms, ofItemAtPath: fakeBin.path)
        await vm.importMCPServer(name: "fake-mcp", command: fakeBin.path, arguments: "", environment: "")
        try await settle(300)
        let localMeta = fx.localRoot.appendingPathComponent("plugins-meta/installed.json")
        #expect(FileManager.default.fileExists(atPath: localMeta.path), "本地根应写入元数据清单")
        let manifest = PluginMetadataStore.load(from: localMeta)
        #expect(manifest.plugins.contains { $0.name == "fake-mcp" && $0.origin == .localMCP })
        // 本地单根：reconcile 恒 no-op，待重导名单恒空
        await vm.reconcilePluginMetadata()
        #expect(vm.mcpPendingReimportNames.isEmpty)
        _ = mcpConfigURL
    }

    @Test("文件型主题包：导入 → 安装 + 清单落盘 → 停用删除目录 + 清单清除")
    func fileThemePackageLifecycle() async throws {
        let fx = try AppWorkspaceFixture()
        defer { fx.cleanup() }
        let (vm, _) = makeWorkspaceVM(fx)
        await vm.loadPluginsInfrastructure()

        let specFile = fx.tempDir.appendingPathComponent("mytheme.json")
        let json = "{\"id\":\"lifecase\",\"name\":\"生命周期主题\",\"accentHex\":\"#ABCDEF\"}"
        try Data(json.utf8).write(to: specFile)
        vm.importThemePackage(fileURL: specFile)
        try await settle(500)

        // 已安装且元数据落盘
        #expect(vm.fileThemePackageIDs.contains("theme-file-lifecase"))
        let pkgDir = fx.localRoot.appendingPathComponent("themes/lifecase")
        #expect(FileManager.default.fileExists(atPath: pkgDir.path))
        let manifest = PluginMetadataStore.load(from: fx.localRoot.appendingPathComponent("plugins-meta/installed.json"))
        #expect(manifest.plugins.contains { $0.id == "theme-file-lifecase" && $0.origin == .fileThemePackage })
        // 主题选项可见（ThemeProviderPlugin 自动进入主题插件机制）
        await vm.refreshThemes()
        #expect(vm.themeOptions.contains { $0.id == "lifecase" })

        // 停用（卸载）→ 包目录删除 + 清单条目清除
        guard let item = vm.plugins.first(where: { $0.id == "theme-file-lifecase" }) else {
            Issue.record("插件列表未找到文件型主题包")
            return
        }
        vm.togglePlugin(item)
        try await settle(500)
        #expect(!FileManager.default.fileExists(atPath: pkgDir.path), "停用后包目录应删除")
        let manifest2 = PluginMetadataStore.load(from: fx.localRoot.appendingPathComponent("plugins-meta/installed.json"))
        #expect(!manifest2.plugins.contains { $0.id == "theme-file-lifecase" })
        await vm.refreshThemes()
        #expect(!vm.themeOptions.contains { $0.id == "lifecase" })
    }

    /// 向上查找 .git 定位仓库根（首选测试进程 cwd = SwiftPM 包根；测试二进制在 Xcode 工具链目录，#file 为模块相对路径，均不可靠）
    private static func findRepoRoot() -> URL? {
        let fm = FileManager.default
        let candidates = [
            URL(fileURLWithPath: fm.currentDirectoryPath),
            URL(fileURLWithPath: Bundle.main.bundlePath),
            URL(fileURLWithPath: CommandLine.arguments.first ?? ""),
        ]
        for start in candidates {
            var dir = start.standardizedFileURL
            for _ in 0 ... 12 {
                if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                    return dir
                }
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path {
                    break
                }
                dir = parent
            }
        }
        return nil
    }

    @Test("真实样例包：demos/community-theme-demo/spec.json 可解析（P0.4.3 验收样例防漂移）")
    func realSampleThemePackage() throws {
        guard let repoRoot = Self.findRepoRoot() else {
            Issue.record("无法定位仓库根（cwd/bundle/argv0 向上均无 .git）")
            return
        }
        let sample = repoRoot.appendingPathComponent("demos/community-theme-demo/spec.json")
        let sampleExists = FileManager.default.fileExists(atPath: sample.path)
        try #require(sampleExists, "样例主题包缺失：\(sample.path)")
        let spec = try ThemePackageImporter.parse(fileURL: sample)
        #expect(spec.id == "community-demo-teal")
        #expect(spec.accentHex == "#0FB5A6")
        #expect(spec.name.contains("社区样例"))
    }
}
