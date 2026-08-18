import Foundation
import HarnessCore
import os.log
@testable import ServiceContainer
import Testing
import XCTest

private extension PluginContext {
    /// 测试用插件上下文（各内置插件方法均忽略 context 参数，仅验证生命周期）
    static func testContext() -> PluginContext {
        PluginContext(
            container: ServiceContainer(),
            eventBus: EventBus(),
            configuration: PluginConfiguration(),
            logger: Logger(subsystem: "test", category: "core"),
            cancellation: Cancellation()
        )
    }
}

@Suite("BuiltInPlugins 生命周期与目录")
struct BuiltInPluginTests {
    @Test("文件系统插件：manifest 与 start/stop 生命周期")
    func filePluginLifecycle() async throws {
        let plugin = BuiltInFilesystemPlugin()
        XCTAssertEqual(plugin.manifest.id.rawValue, "file-system")
        XCTAssertEqual(plugin.manifest.name, "文件系统")
        XCTAssertEqual(plugin.manifest.version, PluginVersion(major: 1, minor: 0, patch: 0))
        XCTAssertEqual(plugin.manifest.permissions, [.filesystemRead, .filesystemWrite])
        XCTAssertTrue(plugin.manifest.permissions.contains(.filesystemWrite))

        XCTAssertFalse(plugin.isActive)
        try await plugin.initialize(context: .testContext())
        XCTAssertFalse(plugin.isActive, "initialize 后尚未 start")
        try await plugin.start(context: .testContext())
        XCTAssertTrue(plugin.isActive)
        await plugin.stop(context: .testContext())
        XCTAssertFalse(plugin.isActive)
        // 协议默认 healthCheck
        let health = await plugin.healthCheck()
        XCTAssertEqual(health.status, .unknown)
    }

    @Test("终端插件：manifest 与 start/stop 生命周期")
    func terminalPluginLifecycle() async throws {
        let plugin = BuiltInTerminalPlugin()
        XCTAssertEqual(plugin.manifest.id.rawValue, "terminal")
        XCTAssertEqual(plugin.manifest.name, "终端")
        XCTAssertEqual(plugin.manifest.permissions, [.shellExecution, .terminalAccess])
        // 高危权限等级
        XCTAssertEqual(plugin.manifest.permissions.first?.level, .high)

        XCTAssertFalse(plugin.isActive)
        try await plugin.initialize(context: .testContext())
        try await plugin.start(context: .testContext())
        XCTAssertTrue(plugin.isActive)
        await plugin.stop(context: .testContext())
        XCTAssertFalse(plugin.isActive)
    }

    @Test("重复 start/stop 幂等")
    func repeatedStartStopIsIdempotent() async throws {
        let plugin = BuiltInFilesystemPlugin()
        let ctx = PluginContext.testContext()
        try await plugin.start(context: ctx)
        try await plugin.start(context: ctx)
        XCTAssertTrue(plugin.isActive)
        await plugin.stop(context: ctx)
        await plugin.stop(context: ctx)
        XCTAssertFalse(plugin.isActive)
    }

    @Test("目录包含两个内置插件且权限文案齐全")
    func catalogContainsBothBuiltIns() throws {
        XCTAssertEqual(BuiltInPluginCatalog.info.count, 2)
        let fs = try #require(BuiltInPluginCatalog.info["file-system"])
        XCTAssertEqual(fs.permissions, ["文件读取", "文件写入"])
        XCTAssertFalse(fs.description.isEmpty)
        let term = try #require(BuiltInPluginCatalog.info["terminal"])
        XCTAssertEqual(term.permissions, ["Shell 执行", "终端访问"])
        XCTAssertFalse(term.description.isEmpty)
        #expect(BuiltInPluginCatalog.info["nope"] == nil)
    }
}
