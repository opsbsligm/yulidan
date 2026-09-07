import AppKit
@testable import HarnessApp
import Testing

// MARK: - 主窗底实底装配（D-10(b) 09-07 回退 · A 层进程内结构断言）

//
// 方向反转护栏（09-06 制度㊾-3 同源做法，与 glassFaceCount 上限护栏同一口径）：
//   D-10(a)「透明窗底让玻璃采桌面」在用户实机被两次目检否决——全屏玻璃面把用户壁纸当采样源，
//   界面色相随壁纸漂移（暖棕壁纸 ⇒ 侧栏浓橙）。玻璃是否真实采到桌面（透窗实况）无静默像素通道
//   （ImageRenderer 不渲染 glassEffect，BENCHMARK §4）⇒ 改为锁定 AppKit 层可证明的窗口配置事实：
//   主窗必须实底。若有人重新置透明，本用例立即判红；上调须附 A-d 目检通过证据。

@MainActor
@Suite("主窗底实底装配（D-10(b) 回退护栏）")
struct WindowGlassSamplingTests {
    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
    }

    /// 判别力：先把窗口改成 D-10(a) 的透明态，装配后必须回到实底 + 不透明 alpha=1
    @Test("实底装配覆盖透明态并置回 opaque")
    func applyRestoresOpaqueBackdrop() {
        let window = makeWindow()
        // 反例基线（D-10(a) 形态）：透明 + 非 opaque ⇒ 提供判别力，防「不改也过」
        window.isOpaque = false
        window.backgroundColor = .clear
        #expect(!window.isOpaque)
        #expect(window.backgroundColor?.usingColorSpace(.deviceRGB)?.alphaComponent == 0)

        AppDelegate.applyOpaqueBackdrop(to: window)

        #expect(window.isOpaque)
        let bg = window.backgroundColor?.usingColorSpace(.deviceRGB)
        #expect(bg?.alphaComponent == 1)
        #expect(bg == NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB))
    }

    /// 装配后不得残留 clear 背景（语义等价：窗后无任何采样源可穿透到全屏玻璃面）
    @Test("装配后窗底非 clear")
    func backdropIsNotClearAfterApply() {
        let window = makeWindow()
        AppDelegate.applyOpaqueBackdrop(to: window)
        #expect(window.backgroundColor != .clear)
        #expect(window.backgroundColor != nil)
    }
}
