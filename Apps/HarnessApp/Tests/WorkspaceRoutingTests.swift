import Account
import Foundation
@testable import HarnessApp
import LLM
import MCP
import RAG
import Testing

// MARK: - P0.1.5 工作区运行时接线（本地 ⇄ iCloud 双根严格隔离）+ P0.4.3 文件型主题包

//
// 隔离纪律（与既有 App 套件一致）：
// - 全部目录走每用例独立临时目录；不触碰真实 DB / ~/.harness / 真实 KVS
// - AppViewModel 经 init 缝注入 workspaceRouter / sharedRAG / sessionDBURL / mcpConfigURLOverride
// - .serialized：AppViewModel 套件并行时 @MainActor await 点交错，串行最稳

// MARK: - Fakes（复刻 Account 包测试夹具的最小 App 侧版本）

final class AppFakeUbiquityProbe: UbiquityProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var _containerURL: URL?
    var containerURL: URL? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _containerURL
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _containerURL = newValue
        }
    }

    init(containerURL: URL? = nil) {
        _containerURL = containerURL
    }

    func probe(containerIdentifier _: String) -> ICloudProbe {
        ICloudProbe(containerURL: containerURL, hasICloudAccount: true)
    }
}

final class AppFakeKVS: UbiquitousKeyValueStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var data: [String: Data] = [:]

    func set(_ value: Data, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        data[key] = value
    }

    func data(forKey key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return data[key]
    }

    @discardableResult
    func synchronize() -> Bool {
        true
    }
}

final class AppFakeCredentialStore: AppleCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var _stored: StoredAppleAccount?

    func load() throws -> StoredAppleAccount? {
        lock.lock()
        defer { lock.unlock() }
        return _stored
    }

    func save(_ account: StoredAppleAccount) throws {
        lock.lock()
        defer { lock.unlock() }
        _stored = account
    }

    func delete() throws {
        lock.lock()
        defer { lock.unlock() }
        _stored = nil
    }
}

@MainActor
final class AppFakeSigning: AppleSigning {
    var signInCalls = 0

    func signIn(existingUserID _: String?, onResult: @escaping @MainActor (Result<AppleSignInOutcome, Error>) -> Void) {
        signInCalls += 1
        onResult(.success(AppleSignInOutcome(userID: "ws-test-user", email: "ws@test.local", displayName: "WS Test")))
    }

    func cancel() {}

    func credentialState(forUserID _: String) async -> AppleCredentialState {
        .authorized
    }
}

/// 每用例独立：本地根 + 假 iCloud 容器（临时目录）+ 内存 KVS/凭证
@MainActor
final class AppWorkspaceFixture {
    let tempDir: URL
    let localRoot: URL
    let icloudContainer: URL
    let probe: AppFakeUbiquityProbe
    let signing: AppFakeSigning
    let service: AccountService
    /// 全局 UserDefaults 沙箱设置的隔离（防跨 suite 串扰 / 磁盘持久化残留）
    private let prevSandboxRoot: String?

    init(icloudAvailable: Bool = true) throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ws-routing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        localRoot = tempDir.appendingPathComponent("LocalRoot", isDirectory: true)
        icloudContainer = tempDir.appendingPathComponent("iCloudContainer", isDirectory: true)
        try FileManager.default.createDirectory(at: icloudContainer, withIntermediateDirectories: true)
        // 沙箱设置全局生效且持久化：fixture 一律移除，cleanup 恢复原值（VM 测试 hermetic）
        prevSandboxRoot = UserDefaults.standard.string(forKey: "sandboxRoot")
        UserDefaults.standard.removeObject(forKey: "sandboxRoot")
        probe = AppFakeUbiquityProbe(containerURL: icloudAvailable ? icloudContainer : nil)
        signing = AppFakeSigning()
        let rootProvider = WorkspaceRootProvider(localRoot: localRoot, probe: probe)
        service = AccountService(
            rootProvider: rootProvider,
            probe: probe,
            credentialStore: AppFakeCredentialStore(),
            signingFactory: { [signing] in signing },
            settingsURL: tempDir.appendingPathComponent("account.json"),
            kvsStoreFactory: { AppFakeKVS() }
        )
        service.restore()
    }

    /// 登录并进入 icloudReady（fake 即时回调 + settle）
    func signInToICloud() async throws {
        service.signInWithApple()
        try await Task.sleep(for: .milliseconds(150))
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

// MARK: - 套件 1：WorkspaceRouter 纯路由

@MainActor
@Suite("P0.1.5 WorkspaceRouter 路由", .serialized)
struct WorkspaceRouterTests {
    @Test("本地模式：目录集路由本地根 + 骨架物化")
    func localModeRoutes() throws {
        let fx = try AppWorkspaceFixture(icloudAvailable: false)
        defer { fx.cleanup() }
        let router = WorkspaceRouter(accountService: fx.service)
        #expect(router.current.kind == .local)
        #expect(router.isICloud == false)
        #expect(router.agentOutputs == fx.localRoot.appendingPathComponent("agents", isDirectory: true))
        #expect(router.ragIndexURL == fx.localRoot.appendingPathComponent("rag/index.json"))
        #expect(router.pluginMetaURL == fx.localRoot.appendingPathComponent("plugins-meta/installed.json"))
        #expect(router.themeResources == fx.localRoot.appendingPathComponent("themes", isDirectory: true))
        for dir in WorkspaceLayout.allDirectories {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(
                atPath: fx.localRoot.appendingPathComponent(dir).path, isDirectory: &isDir
            )
            #expect(isDir.boolValue, "本地根缺失子目录：\(dir)")
        }
    }

    @Test("登录 iCloud 后 refresh：路由切容器 + 骨架物化；无变化 refresh 返回 false")
    func switchToICloudRoutes() async throws {
        let fx = try AppWorkspaceFixture()
        defer { fx.cleanup() }
        let router = WorkspaceRouter(accountService: fx.service)
        #expect(router.current.kind == .local)

        try await fx.signInToICloud()
        #expect(fx.service.state == .icloudReady)
        #expect(router.refresh(), "模式变化应返回 true")
        #expect(router.current.kind == .icloud)
        let docs = fx.icloudContainer.appendingPathComponent("Documents", isDirectory: true)
        #expect(router.agentOutputs == docs.appendingPathComponent("agents", isDirectory: true))
        #expect(router.ragIndexURL == docs.appendingPathComponent("rag/index.json"))
        #expect(router.pluginMetaURL == docs.appendingPathComponent("plugins-meta/installed.json"))
        #expect(router.themeResources == docs.appendingPathComponent("themes", isDirectory: true))
        for dir in WorkspaceLayout.allDirectories {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: docs.appendingPathComponent(dir).path, isDirectory: &isDir)
            #expect(isDir.boolValue, "iCloud 根缺失子目录：\(dir)")
        }

        #expect(!router.refresh(), "无变化 refresh 应返回 false")
    }

    @Test("切回本地：路由回落本地根")
    func switchBackToLocal() async throws {
        let fx = try AppWorkspaceFixture()
        defer { fx.cleanup() }
        let router = WorkspaceRouter(accountService: fx.service)
        try await fx.signInToICloud()
        _ = router.refresh()

        fx.service.switchToLocalMode()
        #expect(router.refresh())
        #expect(router.current.kind == .local)
        #expect(router.agentOutputs == fx.localRoot.appendingPathComponent("agents", isDirectory: true))
    }

    @Test("sessionCwd 位于 agentOutputs/<sessionID>")
    func sessionCwdShape() throws {
        let fx = try AppWorkspaceFixture(icloudAvailable: false)
        defer { fx.cleanup() }
        let router = WorkspaceRouter(accountService: fx.service)
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

    @Test("缺失 / 损坏 / 版本不符 → 空清单（离线优先不污染运行时）")
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

// MARK: - 套件 3：文件型主题包（P0.4.3 社区主题包兼容）

@Suite("P0.4.3 文件型主题包")
struct FileThemePackageTests {
    private func writeSpec(_ dir: URL, id: String, name: String, accent: String? = "#123456") throws -> URL {
        var spec: [String: String] = ["id": id, "name": name]
        if let accent {
            spec["accentHex"] = accent
        }
        let url = dir.appendingPathComponent("spec.json")
        try JSONEncoder().encode(spec).write(to: url)
        return url
    }

    @Test("导入：spec.json → themes/<id>/ + 插件实例 + loadAll 可重扫")
    func importAndReload() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("themes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("src.json")
        let json = "{\"id\":\"My Theme!\",\"name\":\"我的主题\",\"accentHex\":\"#123456\"}"
        try Data(json.utf8).write(to: source)

        let plugin = try ThemePackageImporter.importPackage(fileURL: source, into: root)
        // id 净化（My Theme! → my-theme）
        #expect(plugin.manifest.id.rawValue == "theme-file-my-theme")
        #expect(plugin.themeSpec.id == "my-theme")
        let expected = root.appendingPathComponent("my-theme/spec.json")
        #expect(FileManager.default.fileExists(atPath: expected.path))
        #expect(ThemePackageImporter.loadAll(in: root).count == 1)

        // 卸载删目录
        ThemePackageImporter.remove(themeID: "my-theme", from: root)
        #expect(!FileManager.default.fileExists(atPath: expected.path))
        #expect(ThemePackageImporter.loadAll(in: root).isEmpty)
    }

    @Test("目录包（内含 spec.json）可导入；缺失 spec.json 报错")
    func directoryPackage() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("themes-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pkgDir = root.appendingPathComponent("pkg")
        try FileManager.default.createDirectory(at: pkgDir, withIntermediateDirectories: true)
        _ = try writeSpec(pkgDir, id: "dircase", name: "目录包")
        let plugin = try ThemePackageImporter.importPackage(fileURL: pkgDir, into: root)
        #expect(plugin.manifest.id.rawValue == "theme-file-dircase")

        let emptyDir = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        #expect((try? ThemePackageImporter.importPackage(fileURL: emptyDir, into: root)) == nil)
    }

    @Test("二次校验：空 id / 非法颜色 / 非法 JSON 拒绝")
    func validationRejects() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("themes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bad = root.appendingPathComponent("bad.json")

        try Data(#"{"id":"  ","name":"x"}"#.utf8).write(to: bad)
        #expect((try? ThemePackageImporter.importPackage(fileURL: bad, into: root)) == nil)

        try Data(#"{"id":"ok","name":"x","accentHex":"red"}"#.utf8).write(to: bad)
        #expect((try? ThemePackageImporter.importPackage(fileURL: bad, into: root)) == nil)

        try Data("not-json".utf8).write(to: bad)
        #expect((try? ThemePackageImporter.importPackage(fileURL: bad, into: root)) == nil)
    }

    @Test("sanitizeID：大小写/非法字符/长度")
    func sanitize() {
        #expect(ThemePackageImporter.sanitizeID("My Theme!") == "my-theme")
        #expect(ThemePackageImporter.sanitizeID("a_b-c9") == "a_b-c9")
        #expect(ThemePackageImporter.sanitizeID("---x---") == "x")
        #expect(ThemePackageImporter.sanitizeID(String(repeating: "a", count: 60)).count == 40)
    }
}

// MARK: - 套件 4：AppViewModel 工作区接线场景

/// 全缝注入：临时 skill/DB/mcpConfig + 假账号路由 + 独立 RAG 实例（e2e 拆分文件复用）
@MainActor
func makeWorkspaceVM(_ fx: AppWorkspaceFixture) -> (vm: AppViewModel, mcpConfigURL: URL) {
    UserDefaults.standard.removeObject(forKey: ThemePluginManager.activeKey)
    let mcpConfigURL = fx.tempDir.appendingPathComponent("mcp/servers.json")
    let ragIndex = fx.tempDir.appendingPathComponent("rag-instance/index.json")
    let vm = AppViewModel(
        skillUserDirectory: fx.tempDir.appendingPathComponent("skills"),
        sessionDBURL: fx.tempDir.appendingPathComponent("sessions.sqlite"),
        mcpConfigURLOverride: mcpConfigURL,
        workspaceRouter: WorkspaceRouter(accountService: fx.service),
        sharedRAG: SharedRAGEngine(indexURL: ragIndex),
        accountService: fx.service
    )
    return (vm, mcpConfigURL)
}

@MainActor
@Suite("AppViewModel P0.1.5 工作区接线", .serialized)
struct AppViewModelWorkspaceRoutingTests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    @Test("新会话 cwd = 活动工作区/agents/<sessionID>（本地根）")
    func newSessionCwdRoutesToWorkspace() throws {
        let fx = try AppWorkspaceFixture(icloudAvailable: false)
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

    @Test("切 iCloud：RAG 重路由落容器 + 新会话 cwd 入容器（旧会话不受影响）")
    func switchToICloudReroutesRuntime() async throws {
        let fx = try AppWorkspaceFixture()
        defer { fx.cleanup() }
        let (vm, _) = makeWorkspaceVM(fx)
        vm.createNewSession(silent: true)
        let oldSession = vm.sessions.first

        // 本地根写入 RAG（模拟本地模式使用）
        let localRag = await vm.sharedRAG.get()
        _ = await localRag.ingestText("local root document", source: "docLocal")
        await localRag.save()

        try await fx.signInToICloud()
        #expect(fx.service.state == .icloudReady)
        try await settle(400) // accountObservation sink Task（refresh + handleWorkspaceRootChanged）

        #expect(vm.workspaceRouter.current.kind == .icloud)
        // 新会话 cwd 入 iCloud 容器
        vm.createNewSession(silent: true)
        let docs = fx.icloudContainer.appendingPathComponent("Documents", isDirectory: true)
        #expect(vm.sessions.first?.metadata.cwd.path.hasPrefix(docs.path) == true)
        // 旧会话 cwd 保持创建时根（不迁移）
        #expect(oldSession?.metadata.cwd.path.hasPrefix(fx.localRoot.path) == true)
        // RAG 已重路由：向新根写入 → 容器 rag/index.json 落盘；新根检索不到本地根旧数据
        let newRag = await vm.sharedRAG.get()
        // 新根 store 不得含本地根旧数据（以文档清单为准；检索相关性可能因共享词元命中，不作泄漏判据）
        #expect(await (newRag.documentIDs()).isEmpty, "新根 store 应为空（本地根数据不迁移）")
        _ = await newRag.ingestText("icloud root document", source: "docCloud")
        await newRag.save()
        #expect(FileManager.default.fileExists(atPath: docs.appendingPathComponent("rag/index.json").path))
        let results = await newRag.retrieve(query: "local root")
        #expect(results.allSatisfy { $0.source == "docCloud" }, "本地根数据不得泄漏进 iCloud 根")
    }

    @Test("MCP 元数据：导入写清单 → 切根对账（二进制存在恢复 / 缺失进待重导）")
    func mcpMetadataPersistAndReconcile() async throws {
        let fx = try AppWorkspaceFixture()
        defer { fx.cleanup() }
        let (vm, mcpConfigURL) = makeWorkspaceVM(fx)

        // 阶段 1（本地根）：导入真实可执行二进制（/bin/echo 类脚本，连接会失败但配置落 servers.json）
        let fakeBin = fx.tempDir.appendingPathComponent("fake-mcp-bin")
        try Data("#!/bin/sh\nexit 1\n".utf8).write(to: fakeBin)
        let perms: [FileAttributeKey: Int] = [.posixPermissions: 0o755]
        try FileManager.default.setAttributes(perms, ofItemAtPath: fakeBin.path)
        await vm.importMCPServer(name: "fake-mcp", command: fakeBin.path, arguments: "", environment: "")
        try await settle(300)
        let localMeta = fx.localRoot.appendingPathComponent("plugins-meta/installed.json")
        #expect(FileManager.default.fileExists(atPath: localMeta.path), "本地根应写入元数据清单")
        var manifest = PluginMetadataStore.load(from: localMeta)
        #expect(manifest.plugins.contains { $0.name == "fake-mcp" && $0.origin == .localMCP })

        // 模拟容器同步（另一设备已把清单同步到 iCloud 根）+ 追加一个二进制缺失条目
        let docs = fx.icloudContainer.appendingPathComponent("Documents", isDirectory: true)
        let cloudMeta = docs.appendingPathComponent("plugins-meta/installed.json")
        try FileManager.default.createDirectory(
            at: cloudMeta.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let missingEntry = PluginMetaEntry(
            id: "missing-id", name: "missing-mcp", version: "1.0.0", origin: .localMCP,
            enabled: true, localPath: "/nonexistent/missing-mcp-bin",
            mcpCommand: ["/nonexistent/missing-mcp-bin"]
        )
        manifest.plugins.append(missingEntry)
        try PluginMetadataStore.save(manifest, to: cloudMeta)

        // 阶段 2：登录切根 → 对账
        try await fx.signInToICloud()
        try await settle(600)
        #expect(vm.workspaceRouter.current.kind == .icloud)
        // 二进制存在 → 恢复进 servers.json 并尝试连接
        let configs = MCPDiscovery.loadConfigs(url: mcpConfigURL)
        #expect(configs.contains { $0.name == "fake-mcp" }, "二进制存在的 MCP 应恢复进配置")
        // 二进制缺失 → 待重新导入
        #expect(vm.mcpPendingReimportNames.contains("missing-mcp"))
        #expect(!vm.mcpPendingReimportNames.contains("fake-mcp"))
    }

    @Test("文件型主题包：导入 → 安装 + 清单落盘 → 停用删除目录 + 清单清除")
    func fileThemePackageLifecycle() async throws {
        let fx = try AppWorkspaceFixture(icloudAvailable: false)
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
