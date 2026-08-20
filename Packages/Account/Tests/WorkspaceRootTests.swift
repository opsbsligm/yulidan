@testable import Account
import Foundation
import Testing

/// 双存储隔离：双根解析 / 目录契约物化 / 严格隔离
struct WorkspaceRootTests {
    @Test func localRootAlwaysAvailable() {
        let local = URL(fileURLWithPath: "/tmp/wr-local-\(UUID().uuidString)")
        let provider = WorkspaceRootProvider(localRoot: local, probe: FakeUbiquityProbe())
        let root = provider.resolveLocal()
        #expect(root.kind == .local)
        #expect(root.rootURL == local)
    }

    @Test func icloudRootResolvesToContainerDocuments() {
        let container = URL(fileURLWithPath: "/tmp/wr-icloud-\(UUID().uuidString)")
        let provider = WorkspaceRootProvider(probe: FakeUbiquityProbe(containerURL: container))
        let root = provider.resolveICloud()
        #expect(root?.kind == .icloud)
        #expect(root?.rootURL == container.appendingPathComponent("Documents", isDirectory: true))
    }

    @Test func icloudRootNilWithoutContainer() {
        let provider = WorkspaceRootProvider(probe: FakeUbiquityProbe(containerURL: nil))
        #expect(provider.resolveICloud() == nil)
    }

    @Test func materializeCreatesStandardLayout() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wr-materialize-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let provider = WorkspaceRootProvider(localRoot: base, probe: FakeUbiquityProbe())
        let root = provider.resolveLocal()

        let created = try provider.materialize(root)
        #expect(created.count == WorkspaceLayout.allDirectories.count)
        for dir in WorkspaceLayout.allDirectories {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: root.url(for: dir).path, isDirectory: &isDir)
            #expect(isDir.boolValue, "缺失目录：\(dir)")
        }
        // 幂等：二次物化不抛错
        _ = try provider.materialize(root)
    }

    @Test func dualRootsAreStrictlyIsolated() {
        let localBase = URL(fileURLWithPath: "/tmp/wr-isolate-local-\(UUID().uuidString)")
        let container = URL(fileURLWithPath: "/tmp/wr-isolate-icloud-\(UUID().uuidString)")
        let provider = WorkspaceRootProvider(localRoot: localBase, probe: FakeUbiquityProbe(containerURL: container))
        let local = provider.resolveLocal()
        guard let icloud = provider.resolveICloud() else {
            Issue.record("icloud root 应为 nil 的仅在无容器场景")
            return
        }
        #expect(local.rootURL != icloud.rootURL)
        #expect(!local.rootURL.path.hasPrefix(icloud.rootURL.path))
        #expect(!icloud.rootURL.path.hasPrefix(local.rootURL.path))
    }

    @Test func layoutContractContainsAllFiveDirectories() {
        #expect(WorkspaceLayout.allDirectories.count == 5)
        #expect(WorkspaceLayout.allDirectories.contains("agents"))
        #expect(WorkspaceLayout.allDirectories.contains("rag"))
        #expect(WorkspaceLayout.allDirectories.contains("plugins-meta"))
        #expect(WorkspaceLayout.allDirectories.contains("themes"))
        #expect(WorkspaceLayout.allDirectories.contains("sync"))
    }
}
