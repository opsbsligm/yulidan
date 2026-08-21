import HarnessCore
import ServiceContainer

/// 本地内置目录源：把 Harness 内置插件上架为市场条目。
/// 市场层对来源无感知，后续可追加远程源 / 本地目录源而不改 UI。
struct LocalBuiltInMarketplaceSource: PluginSource, Sendable {
    let name = "harness-local"

    func fetchListings() async throws -> [PluginListing] {
        [
            PluginListing(plugin: BuiltInFilesystemPlugin()),
            PluginListing(plugin: BuiltInTerminalPlugin()),
            // P0.4⑤ 依赖缺失 UI 演示条目（声明依赖 terminal ≥1.0.0）
            PluginListing(plugin: BuiltInTerminalPlusPlugin()),
        ]
    }
}
