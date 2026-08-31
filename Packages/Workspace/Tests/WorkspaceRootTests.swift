import Foundation
import Testing
@testable import Workspace

/// WorkspaceRoot 纯逻辑全覆盖（2026-08-31 R3 覆盖率收口：<90% 文件清零）
/// 约定：一切文件操作限定在 .temporaryDirectory 隔离目录内，不触碰真实 Application Support。
struct WorkspaceRootTests {
    /// 隔离临时根（每测试独立 UUID 路径，免清理互踩）
    private func tempRoot(_: String = #function) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceRootTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    // MARK: - WorkspaceRoot.url(for:)

    @Test func urlAppendsDirectoryComponent() {
        let root = WorkspaceRoot(kind: .local, rootURL: URL(fileURLWithPath: "/tmp/unit-root", isDirectory: true))
        let target = root.url(for: WorkspaceLayout.agentOutputs)
        #expect(target.path == "/tmp/unit-root/agents")
        // 五目录契约逐名映射（防目录名漂移破坏既有磁盘布局）
        #expect(root.url(for: WorkspaceLayout.ragStore).lastPathComponent == "rag")
        #expect(root.url(for: WorkspaceLayout.pluginMeta).lastPathComponent == "plugins-meta")
        #expect(root.url(for: WorkspaceLayout.themeResources).lastPathComponent == "themes")
        #expect(root.url(for: WorkspaceLayout.memoryStore).lastPathComponent == "memory")
    }

    @Test func layoutContractIsFiveDirectoriesInOrder() {
        #expect(WorkspaceLayout.allDirectories == ["agents", "rag", "plugins-meta", "themes", "memory"])
    }

    @Test func kindCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(WorkspaceKind.local)
        let decoded = try JSONDecoder().decode(WorkspaceKind.self, from: data)
        #expect(decoded == .local)
        #expect(WorkspaceKind.local.rawValue == "local")
    }

    // MARK: - WorkspaceRootProvider.resolveLocal

    @Test func resolveLocalUsesInjectedRoot() {
        let injected = URL(fileURLWithPath: "/tmp/injected-root", isDirectory: true)
        let provider = WorkspaceRootProvider(localRoot: injected)
        let root = provider.resolveLocal()
        #expect(root.kind == .local)
        #expect(root.rootURL == injected)
    }

    @Test func defaultInitFallsBackToApplicationSupportHarness() {
        // 默认分支只计算 URL，不落盘；断言尾段契约，不依赖具体前缀
        let provider = WorkspaceRootProvider()
        let root = provider.resolveLocal()
        #expect(root.kind == .local)
        #expect(root.rootURL.lastPathComponent == "Harness")
        #expect(root.rootURL.path.hasSuffix("Harness"))
    }

    // MARK: - materialize（成功 + 幂等 + 失败分支）

    @Test func materializeCreatesAllFiveDirectories() throws {
        let provider = WorkspaceRootProvider(localRoot: tempRoot("materialize"))
        let urls = try provider.materialize(provider.resolveLocal())
        #expect(urls.count == WorkspaceLayout.allDirectories.count)
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            #expect(fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue,
                    "缺失目录骨架：\(url.path)")
        }
    }

    @Test func materializeIsIdempotent() throws {
        let provider = WorkspaceRootProvider(localRoot: tempRoot("idempotent"))
        let first = try provider.materialize(provider.resolveLocal())
        let second = try provider.materialize(provider.resolveLocal())
        #expect(first == second)
    }

    @Test func materializeThrowsWhenRootPathOccupiedByFile() throws {
        // 失败分支：根路径被普通文件占用 → createDirectory 抛出并透传
        let occupied = tempRoot("occupied")
        let fm = FileManager.default
        try fm.createDirectory(at: occupied.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: occupied) // 根本身是文件
        defer { try? fm.removeItem(at: occupied) }
        let provider = WorkspaceRootProvider(localRoot: occupied)
        #expect(throws: (any Error).self) {
            try provider.materialize(provider.resolveLocal())
        }
    }
}
