import AppKit
@testable import HarnessApp
import ServiceContainer
import SwiftUI
import Testing

// MARK: - 主题即时生效·离屏渲染验证（ImageRenderer，锁屏/无显示器可跑）

/// 覆盖 R1 §10.3 #6 的功能内核：「启用主题 → UI 即时更新（无需重启 App）」——
/// vm.applyTheme 后不做任何重启/刷新，重新渲染的位图主通道必须立即随主题翻转（蓝系↔橙系），
/// 还原后像素逐点复原。手段为 SwiftUI 官方 ImageRenderer 离屏渲染（进程内、无窗口服务器依赖）。
/// 系统玻璃折射 / 真机色准 / NSOpenPanel 导入链路仍归真机抽样（P1_STAGE_REPORT §10.3）。
@MainActor
@Suite("主题切换即时生效（离屏渲染）", .serialized)
struct ThemeLiveRenderTests {
    init() {
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    /// 复刻 AppViewModelThemePluginTests 的构造缝（含 activeKey 预清，防跨套件残留态）
    private func makeVM() async -> AppViewModel {
        let mcpConfigURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-render-\(UUID().uuidString)")
            .appendingPathComponent("servers.json")
        UserDefaults.standard.removeObject(forKey: ThemePluginManager.activeKey)
        let vm = AppViewModel(
            skillUserDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("harness-render-skills-\(UUID().uuidString)"),
            sessionDBURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("harness-render-\(UUID().uuidString).sqlite"),
            mcpConfigURLOverride: mcpConfigURL
        )
        vm.llmConfig.provider = .local
        await vm.loadPluginsInfrastructure()
        await vm.refreshThemes()
        return vm
    }

    /// 主题探针：满铺 accent 色块（采样任何中心点必命中主题色，无布局歧义）
    private struct Probe: View {
        let spec: ThemeSpec
        var body: some View {
            spec.accentColor
                .frame(width: 64, height: 64)
        }
    }

    private func renderBitmap(_ view: some View) -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1 // 像素与点一一对应
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              rep.pixelsWide > 0 else {
            Issue.record("ImageRenderer 离屏渲染失败")
            return NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                    isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0, bitsPerPixel: 0)!
        }
        return rep
    }

    /// 采样并统一 sRGB 归一（消除设备色空间/广色域表示差异）
    private func sample(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let raw = rep.colorAt(x: x, y: y) ?? .black
        let c = raw.usingColorSpace(.sRGB) ?? raw
        return (c.redComponent, c.greenComponent, c.blueComponent)
    }

    private func diffPoints(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Int {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return .max }
        var n = 0
        for ix in stride(from: 2, to: a.pixelsWide, by: 8) {
            for iy in stride(from: 2, to: a.pixelsHigh, by: 8) {
                let p1 = sample(a, ix, iy), p2 = sample(b, ix, iy)
                if abs(p1.r - p2.r) > 0.03 || abs(p1.g - p2.g) > 0.03 || abs(p1.b - p2.b) > 0.03 {
                    n += 1
                }
            }
        }
        return n
    }

    @Test("applyTheme(落日渐橙) → 位图即时变化且主通道蓝→橙翻转；还原基准像素复原（全程无重启）")
    func themeSwitchReflectsInRenderWithoutRestart() async throws {
        let vm = await makeVM()
        defer { vm.applyTheme(id: ThemeSpec.systemBaseline.id) }
        try #require(vm.themeOptions.contains { $0.id == "sunset" })

        // 初始系统基准：accentHex=nil → 系统蓝回退（蓝主通道）。
        // 注：ImageRenderer 输出为显示器色空间且 Color.blue 为动态 systemBlue
        // （深色外观下 RGB≈(0.13,0.62,1)），绝对值断言不稳定 → 采用「通道主导序」
        // 断言：蓝系(B 主导) ↔ 橙系(R 主导) 通道序翻转，对色彩空间换算鲁棒；
        // hex→Color 数值正确性由 ThemePluginManager 既有 hex 解析单测覆盖。
        #expect(vm.activeThemeSpec.id == ThemeSpec.systemBaseline.id)
        let baseRep = renderBitmap(Probe(spec: vm.activeThemeSpec))
        let base = sample(baseRep, 32, 32)
        #expect(base.b > base.r && base.b >= base.g, "系统基准=蓝系主导，实测 \(base)")

        // 切换主题插件（不重启、不刷新，重新渲染即取新 spec）
        vm.applyTheme(id: "sunset")
        #expect(vm.activeThemeSpec.id == "sunset")
        let sunsetRep = renderBitmap(Probe(spec: vm.activeThemeSpec))
        let hot = sample(sunsetRep, 32, 32)
        // sunset accentHex=#FF9F0A：橙系 R 主导且高位（P3/sRGB 下 R 均 ≥0.9）
        #expect(hot.r > hot.b && hot.r > 0.7, "accent 应即时为橙系主导致色，实测 \(hot)")
        #expect(hot.g > hot.b, "落日渐橙应保留 G>B 的暖色特征，实测 \(hot)")
        #expect(diffPoints(baseRep, sunsetRep) > 20, "蓝→橙切换后全色块位图应逐点不一致（采样网格 8×8）")

        // 还原基准 → 像素复原（无重启回落）
        vm.applyTheme(id: ThemeSpec.systemBaseline.id)
        #expect(vm.activeThemeSpec.id == ThemeSpec.systemBaseline.id)
        let backRep = renderBitmap(Probe(spec: vm.activeThemeSpec))
        let back = sample(backRep, 32, 32)
        #expect(back.b > back.r && back.b >= back.g, "还原后应回到蓝系主导，实测 \(back)")
        #expect(diffPoints(backRep, baseRep) == 0, "还原后位图应与初始基准逐点一致")
    }
}
